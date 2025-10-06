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

    // Photo finish overlay
    @Published var showPhotoFinishOverlay = true
    @Published var finishLineTopX: Double = 0.5 // Normalized X position for top of line (0.0 to 1.0)
    @Published var finishLineBottomX: Double = 0.5 // Normalized X position for bottom of line (0.0 to 1.0)


    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    private var rateObserver: AnyCancellable?

    var timingModel: RaceTimingModel?

    init() {
        self.player = AVPlayer()
        setupObservers()
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
        zoomScale = max(1.0, min(newScale, 5.0))
    }

    func endPinchGesture() {
        isPinchGestureActive = false
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
}