import AVFoundation
import Combine

class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var isSeekingOutsideVideo = false

    // Zoom controls
    @Published var zoomScale: Double = 1.0
    @Published var zoomOffset: CGSize = .zero

    // Pan gesture state
    private var panStartOffset: CGSize = .zero
    private var isPanGestureActive: Bool = false

    // Pinch gesture state
    private var pinchStartScale: Double = 1.0
    private var isPinchGestureActive: Bool = false

    // Line drag state
    private var lineDragStartTopX: Double = 0.0
    private var lineDragStartBottomX: Double = 0.0
    private var isLineDragActive: Bool = false

    // Photo finish overlay
    @Published var showPhotoFinishOverlay = true
    @Published var finishLineTopX: Double = 0.5 // Normalized X position for top of line (0.0 to 1.0)
    @Published var finishLineBottomX: Double = 0.5 // Normalized X position for bottom of line (0.0 to 1.0)

    // Virtual finish line — Phase A motion inspection (separate from photo-finish overlay above)
    @Published var showDetectionLine: Bool = false
    @Published var showMotionOverlay: Bool = false
    @Published var detectionLine: DetectionLine?
    @Published var motionThreshold: Int = 12  // 0..255 frame-diff threshold (debug slider)
    /// Last completed sweep — bound to a graph in the Race Timeline.
    @Published var motionSweepRows: [SweepRow] = []
    @Published var motionCrossings: [CrossingEvent] = []
    // Detection-line drag state
    private var detectionLineDragStart: DetectionLine?


    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    private var rateObserver: AnyCancellable?
    private var finishLineCancellables = Set<AnyCancellable>()
    private var sessionFinishLineObserver: AnyCancellable?
    /// Set while we're syncing the finish line FROM session data into PlayerViewModel,
    /// to suppress the reverse write that would otherwise overwrite the session value.
    private var isApplyingSessionFinishLine = false

    var timingModel: RaceTimingModel? {
        didSet {
            observeSessionFinishLine()
        }
    }

    init() {
        self.player = AVPlayer()
        setupObservers()
        loadSavedFinishLine()
        setupFinishLinePersistence()
    }

    // Persist the photo finish overlay position so it survives across sessions / app launches.
    // Most users set the line once (matching camera install) and want it to stay put.
    private func loadSavedFinishLine() {
        if let top = UserDefaults.standard.object(forKey: "finishLineTopX") as? Double {
            finishLineTopX = max(0.0, min(1.0, top))
        }
        if let bottom = UserDefaults.standard.object(forKey: "finishLineBottomX") as? Double {
            finishLineBottomX = max(0.0, min(1.0, bottom))
        }
    }

    private func setupFinishLinePersistence() {
        // Debounce so we don't hammer UserDefaults / sessionData during a drag.
        $finishLineTopX
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] value in
                guard let self = self, !self.isApplyingSessionFinishLine else { return }
                UserDefaults.standard.set(value, forKey: "finishLineTopX")
                self.timingModel?.sessionData?.finishLineTopX = value
            }
            .store(in: &finishLineCancellables)

        $finishLineBottomX
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] value in
                guard let self = self, !self.isApplyingSessionFinishLine else { return }
                UserDefaults.standard.set(value, forKey: "finishLineBottomX")
                self.timingModel?.sessionData?.finishLineBottomX = value
            }
            .store(in: &finishLineCancellables)
    }

    /// When a session is loaded into the timing model, mirror its finish-line position
    /// into PlayerViewModel. If the session has no values, leave whatever is currently set
    /// (which comes from UserDefaults as the per-app default).
    private func observeSessionFinishLine() {
        sessionFinishLineObserver?.cancel()
        guard let model = timingModel else { return }
        sessionFinishLineObserver = model.$sessionData
            .compactMap { $0 }
            .sink { [weak self] session in
                guard let self = self else { return }
                self.isApplyingSessionFinishLine = true
                if let top = session.finishLineTopX {
                    self.finishLineTopX = max(0.0, min(1.0, top))
                }
                if let bottom = session.finishLineBottomX {
                    self.finishLineBottomX = max(0.0, min(1.0, bottom))
                }
                self.isApplyingSessionFinishLine = false
            }
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }

    private func setupObservers() {
        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        rateObserver = player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.isPlaying = rate != 0
            }
    }

    func loadVideo(url: URL) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        statusObserver = playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.duration = playerItem.asset.duration.seconds
                }
            }

        player.replaceCurrentItem(with: playerItem)
        player.pause()
    }

    func seek(to time: Double, precise: Bool = false) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        if precise {
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: cmTime)
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func seekToNextFrame() {
        guard let currentItem = player.currentItem else { return }

        let frameRate = currentItem.asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30.0
        let frameDuration = 1.0 / Double(frameRate)
        let nextTime = currentTime + frameDuration

        if nextTime <= duration {
            seek(to: nextTime, precise: true)
        }
    }

    func seekToPreviousFrame() {
        guard let currentItem = player.currentItem else { return }

        let frameRate = currentItem.asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30.0
        let frameDuration = 1.0 / Double(frameRate)
        let previousTime = max(0, currentTime - frameDuration)

        seek(to: previousTime, precise: true)
    }

    // MARK: - Zoom Controls

    func zoomIn() {
        zoomScale = min(zoomScale * 1.25, 5.0) // Max zoom 5x
    }

    func zoomOut() {
        zoomScale = max(zoomScale / 1.25, 1.0) // Min zoom 1x (original size)
    }

    func resetZoom() {
        zoomScale = 1.0
        zoomOffset = .zero
    }

    func setZoom(_ scale: Double) {
        zoomScale = max(1.0, min(scale, 5.0))
    }

    func startPinchGesture() {
        pinchStartScale = zoomScale
    }

    func updatePinchGesture(magnification: Double) {
        // Start gesture if not already active
        if !isPinchGestureActive {
            startPinchGesture()
            isPinchGestureActive = true
        }

        let newScale = pinchStartScale * magnification
        // Allow temporary zoom below 1.0 during gesture for better responsiveness
        zoomScale = max(0.5, min(newScale, 5.0))
    }

    func endPinchGesture() {
        isPinchGestureActive = false
        // Snap back to minimum 1.0 zoom when gesture ends
        if zoomScale < 1.0 {
            zoomScale = 1.0
        }
    }

    func panVideo(by offset: CGSize) {
        let maxOffset: Double = 200 // Limit pan distance
        let newX = max(-maxOffset, min(maxOffset, zoomOffset.width + offset.width))
        let newY = max(-maxOffset, min(maxOffset, zoomOffset.height + offset.height))
        zoomOffset = CGSize(width: newX, height: newY)
    }

    func startPanGesture() {
        panStartOffset = zoomOffset
    }

    func updatePanGesture(translation: CGSize) {
        // Start gesture if not already active
        if !isPanGestureActive {
            startPanGesture()
            isPanGestureActive = true
        }

        // Add translation to the starting offset, no need to adjust for zoom scale
        let newOffset = CGSize(
            width: panStartOffset.width + translation.width,
            height: panStartOffset.height + translation.height
        )

        // Dynamic max offset based on zoom level
        let maxOffset: Double = 200 * zoomScale
        let newX = max(-maxOffset, min(maxOffset, newOffset.width))
        let newY = max(-maxOffset, min(maxOffset, newOffset.height))
        zoomOffset = CGSize(width: newX, height: newY)
    }

    func endPanGesture() {
        isPanGestureActive = false
    }


    // MARK: - Photo Finish Overlay

    func togglePhotoFinishOverlay() {
        showPhotoFinishOverlay.toggle()
    }

    func setFinishLineTopX(_ x: Double) {
        finishLineTopX = max(0.0, min(1.0, x))
    }

    func setFinishLineBottomX(_ x: Double) {
        finishLineBottomX = max(0.0, min(1.0, x))
    }

    func moveFinishLineHorizontally(by deltaX: Double) {
        let newTopX = finishLineTopX + deltaX
        let newBottomX = finishLineBottomX + deltaX
        finishLineTopX = max(0.0, min(1.0, newTopX))
        finishLineBottomX = max(0.0, min(1.0, newBottomX))
    }

    func startLineDrag() {
        lineDragStartTopX = finishLineTopX
        lineDragStartBottomX = finishLineBottomX
        isLineDragActive = true
    }

    func updateLineDragWithDelta(startX: Double, currentX: Double) {
        if !isLineDragActive {
            startLineDrag()
        }

        // Calculate delta from the actual start location
        let deltaX = currentX - startX

        let newTopX = lineDragStartTopX + deltaX
        let newBottomX = lineDragStartBottomX + deltaX

        finishLineTopX = max(0.0, min(1.0, newTopX))
        finishLineBottomX = max(0.0, min(1.0, newBottomX))
    }

    func endLineDrag() {
        isLineDragActive = false
    }

    // MARK: - Virtual Finish Line (Phase A) — detection-line editing

    func toggleDetectionLine() { showDetectionLine.toggle() }
    func toggleMotionOverlay() { showMotionOverlay.toggle() }

    /// Create or replace the detection line with the given normalized endpoints.
    /// Coordinates are clamped to [0,1].
    func setDetectionLine(p1: CGPoint, p2: CGPoint) {
        let cp1 = CGPoint(x: clamp01(p1.x), y: clamp01(p1.y))
        let cp2 = CGPoint(x: clamp01(p2.x), y: clamp01(p2.y))
        if var existing = detectionLine {
            existing.p1 = cp1
            existing.p2 = cp2
            detectionLine = existing
        } else {
            detectionLine = DetectionLine(p1: cp1, p2: cp2)
        }
    }

    func clearDetectionLine() { detectionLine = nil }

    /// Drag a single endpoint of the detection line. `which` is 1 for p1, 2 for p2.
    func setDetectionLineEndpoint(_ which: Int, to point: CGPoint) {
        guard var line = detectionLine else { return }
        let clamped = CGPoint(x: clamp01(point.x), y: clamp01(point.y))
        if which == 1 { line.p1 = clamped } else { line.p2 = clamped }
        detectionLine = line
    }

    /// Begin a bodily drag of the detection line (records starting state for delta math).
    /// Idempotent — safe to call repeatedly during a gesture; captures start state only once.
    func beginDetectionLineDrag() {
        if detectionLineDragStart == nil {
            detectionLineDragStart = detectionLine
        }
    }

    /// Apply a translation (in normalized coords) to both endpoints from the drag start.
    func updateDetectionLineDrag(translationNormalized: CGSize) {
        guard let start = detectionLineDragStart else { return }
        let dx = translationNormalized.width
        let dy = translationNormalized.height
        // Clamp so the line stays inside the frame (slide together)
        let p1 = CGPoint(x: start.p1.x + dx, y: start.p1.y + dy)
        let p2 = CGPoint(x: start.p2.x + dx, y: start.p2.y + dy)
        // If either endpoint would leave the frame, clip the translation by the worst-offending axis.
        let minX = min(p1.x, p2.x), maxX = max(p1.x, p2.x)
        let minY = min(p1.y, p2.y), maxY = max(p1.y, p2.y)
        var adjDx = dx, adjDy = dy
        if minX < 0 { adjDx -= minX }
        if maxX > 1 { adjDx -= (maxX - 1) }
        if minY < 0 { adjDy -= minY }
        if maxY > 1 { adjDy -= (maxY - 1) }
        var line = start
        line.p1 = CGPoint(x: start.p1.x + adjDx, y: start.p1.y + adjDy)
        line.p2 = CGPoint(x: start.p2.x + adjDx, y: start.p2.y + adjDy)
        detectionLine = line
    }

    func endDetectionLineDrag() { detectionLineDragStart = nil }

    private func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
}