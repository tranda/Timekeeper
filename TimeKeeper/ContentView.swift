import SwiftUI
import AVKit
import UniformTypeIdentifiers
import Combine

// Custom AVPlayerView without controls
struct AVPlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView_Internal {
        let view = AVPlayerView_Internal()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView_Internal, context: Context) {
        nsView.player = player
    }
}

class AVPlayerView_Internal: AVKit.AVPlayerView {
    override func awakeFromNib() {
        super.awakeFromNib()
        self.controlsStyle = .none
    }

    // Prevent AVKit from grabbing keyboard focus.
    // AVPlayerView has built-in arrow-key bindings for frame-stepping; once it becomes
    // first responder it consumes left/right via paths that bypass our local NSEvent
    // monitor, which is why timeline arrow navigation stopped responding after the
    // first press.
    override var acceptsFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }
}

struct ContentView: View {
    /// Phase A motion-inspection feature flag — toggleable in Preferences.
    /// All supporting code stays in place; UI is hidden when this is false.
    @AppStorage("motionInspectionEnabled") private var motionInspectionEnabled: Bool = false

    @ObservedObject var captureManager: CaptureManager
    @StateObject private var playerViewModel = PlayerViewModel()
    @StateObject private var timingModel = RaceTimingModel()
    @State private var outputFolderURL: URL?
    @State private var isRecording = false
    @State private var recordedVideoURL: URL?
    @State private var exportProgress: Double = 0
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var syncToRaceTime = false
    @State private var keyMonitor: Any? = nil
    @State private var triggerLaneSelection = false
    @State private var isReviewMode = false
    @State private var markTimelineDataAsUnsaved: () -> Void = {}

    // Virtual finish line — Phase A motion inspection
    @State private var motionOverlayImage: CGImage? = nil
    @State private var motionOverlayTask: Task<Void, Never>? = nil
    @State private var showMotionSweepSheet = false
    @State private var motionEnergy: Int = 0
    @State private var motionCentroid: Double = 0
    @State private var motionMaxRecent: Int = 1   // running max for bar normalization
    @State private var motionRoiHalfWidthPx: Int = 40
    @State private var motionTStart: Double = 0.0   // analysis sub-segment start (along line)
    @State private var motionTEnd: Double = 1.0     // analysis sub-segment end (along line)

    var body: some View {
        HStack(spacing: 0) {
            // Left side - Controls
            VStack(alignment: .leading, spacing: 0) {
                RaceTimingPanel(timingModel: timingModel, captureManager: captureManager, playerViewModel: playerViewModel, isReviewMode: $isReviewMode, onTimelineDataChanged: $markTimelineDataAsUnsaved)
            }
            .frame(minWidth: 600, idealWidth: 700, maxWidth: 800)
            .padding(.horizontal)

            Divider()

            // Right side - Video preview and timeline (responsive)
            VStack(spacing: 10) {
                // Video section
                GeometryReader { geometry in
                    VStack(spacing: 10) {
                        // Show camera preview only when NOT in review mode
                        if captureManager.captureSession != nil && !isReviewMode {
                            VStack(spacing: 5) {
                                Text("Live Camera")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                // Landscape video dimensions (16:9 aspect ratio) - show actual recording format
                                let maxWidth = min(geometry.size.width * 0.9, 800)
                                let videoHeight = maxWidth * (9.0 / 16.0)
                                let videoWidth = maxWidth

                                HStack {
                                    Spacer()
                                    VideoPreviewView(session: captureManager.captureSession!)
                                        .frame(width: videoWidth, height: videoHeight)
                                        .background(Color.black)
                                        .cornerRadius(8)
                                    Spacer()
                                }
                            }
                        }

                        // Show recorded video player when in review mode
                        if isReviewMode {
                            VStack(spacing: 5) {
                                if motionInspectionEnabled {
                                HStack(spacing: 12) {
                                    Text("Recorded Video")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Toggle("Motion Overlay", isOn: $playerViewModel.showMotionOverlay)
                                        .toggleStyle(.switch)
                                        .controlSize(.small)
                                        .help("Highlights pixels along the yellow finish line that differ from the rolling baseline (frame-diff)")
                                    HStack(spacing: 4) {
                                        Text("Thr").font(.caption2).foregroundColor(.secondary)
                                        Stepper(value: $playerViewModel.motionThreshold, in: 3...200, step: 1) {
                                            Text("\(playerViewModel.motionThreshold)")
                                                .frame(width: 28, alignment: .trailing)
                                                .font(.caption2.monospacedDigit())
                                        }
                                        .controlSize(.mini)
                                    }
                                    HStack(spacing: 4) {
                                        Text("ROI±").font(.caption2).foregroundColor(.secondary)
                                        Stepper(value: $motionRoiHalfWidthPx, in: 5...200, step: 5) {
                                            Text("\(motionRoiHalfWidthPx)px")
                                                .frame(width: 40, alignment: .trailing)
                                                .font(.caption2.monospacedDigit())
                                        }
                                        .controlSize(.mini)
                                    }
                                    Button("Run Sweep…") {
                                        showMotionSweepSheet = true
                                    }
                                    .controlSize(.small)
                                    .disabled((recordedVideoURL ?? captureManager.lastRecordedURL) == nil)
                                }
                                .padding(.horizontal, 8)

                                // Live energy + centroid display
                                if playerViewModel.showMotionOverlay {
                                    HStack(spacing: 10) {
                                        Text("Motion:").font(.caption2).foregroundColor(.secondary)
                                        let frac = motionMaxRecent > 0 ? Double(motionEnergy) / Double(motionMaxRecent) : 0
                                        ZStack(alignment: .leading) {
                                            Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 160, height: 14)
                                            Rectangle().fill(barColor(for: frac)).frame(width: max(1, CGFloat(frac) * 160), height: 14)
                                        }
                                        Text("energy=\(motionEnergy)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                            .frame(width: 90, alignment: .leading)
                                        Text(motionEnergy > 0 ? String(format: "centroid=%.2f", motionCentroid) : "centroid=–")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                            .frame(width: 110, alignment: .leading)
                                        Button("Reset peak") {
                                            motionMaxRecent = max(1, motionEnergy)
                                        }
                                        .controlSize(.mini)
                                    }
                                    .padding(.horizontal, 8)

                                    // Drag the green handles directly on the finish line; this is just a readout/reset.
                                    HStack(spacing: 10) {
                                        Text(String(format: "Analyzing %.0f%% → %.0f%% of line (drag green handles to adjust)", motionTStart * 100, motionTEnd * 100))
                                            .font(.caption2).foregroundColor(.secondary)
                                        Button("Full line") {
                                            motionTStart = 0; motionTEnd = 1
                                        }
                                        .controlSize(.mini)
                                    }
                                    .padding(.horizontal, 8)
                                }
                                } else {
                                    // Original "Recorded Video" header when motion inspection is disabled.
                                    Text("Recorded Video")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                GeometryReader { outerGeometry in
                                    HStack {
                                        Spacer()
                                        VStack {
                                            // Container view that's 90% of parent size
                                            GeometryReader { geometry in
                                            // Calculate 16:9 aspect ratio container
                                            let aspectRatio = 16.0 / 9.0
                                            let availableWidth = geometry.size.width
                                            let availableHeight = geometry.size.height

                                            let (videoWidth, videoHeight): (CGFloat, CGFloat) = {
                                                if availableWidth / availableHeight > aspectRatio {
                                                    // Available area is wider than 16:9, constrain by height
                                                    let height = availableHeight
                                                    let width = height * aspectRatio
                                                    return (width, height)
                                                } else {
                                                    // Available area is taller than 16:9, constrain by width
                                                    let width = availableWidth
                                                    let height = width / aspectRatio
                                                    return (width, height)
                                                }
                                            }()

                                            ZStack {
                                                // Background for pan gestures - invisible overlay to capture pan gestures
                                                Color.clear
                                                    .contentShape(Rectangle()) // Makes the clear color tappable
                                                    .gesture(
                                                        SimultaneousGesture(
                                                            MagnificationGesture()
                                                                .onChanged { magnification in
                                                                    playerViewModel.updatePinchGesture(magnification: magnification)
                                                                }
                                                                .onEnded { _ in
                                                                    playerViewModel.endPinchGesture()
                                                                },
                                                            DragGesture()
                                                                .onChanged { value in
                                                                    // Pan the unified container when zoomed in
                                                                    if playerViewModel.zoomScale > 1.0 {
                                                                        playerViewModel.updatePanGesture(translation: value.translation)
                                                                    }
                                                                }
                                                                .onEnded { _ in
                                                                    // Pan gesture ended, reset gesture state
                                                                    playerViewModel.endPanGesture()
                                                                }
                                                        )
                                                    )

                                                // Unified video and overlay container with zoom and pan
                                                ZStack {
                                                    AVPlayerView(player: playerViewModel.player)
                                                        .background(Color.black)
                                                        .cornerRadius(8)
                                                        .focusable(false)  // Disable keyboard focus and shortcuts
                                                        .allowsHitTesting(false) // Prevent video from intercepting gestures
                                                        .overlay(
                                                            Rectangle()
                                                                .stroke(Color.red, lineWidth: 1)
                                                                .cornerRadius(8)
                                                        )

                                                    // Photo finish overlay positioned relative to video player
                                                    if playerViewModel.showPhotoFinishOverlay {
                                                        GeometryReader { videoGeometry in
                                                            ZStack {
                                                                // Finish line - positioned at edges for Y coordinate testing
                                                                Path { path in
                                                                    let topX = videoGeometry.size.width * playerViewModel.finishLineTopX
                                                                    let topY: CGFloat = 0 // Top edge
                                                                    let bottomX = videoGeometry.size.width * playerViewModel.finishLineBottomX
                                                                    let bottomY = videoGeometry.size.height // Bottom edge

                                                                    path.move(to: CGPoint(x: topX, y: topY))
                                                                    path.addLine(to: CGPoint(x: bottomX, y: bottomY))
                                                                }
                                                                .stroke(Color.yellow, lineWidth: 1)
                                                                .gesture(
                                                                    DragGesture()
                                                                        .onChanged { value in
                                                                            let startX = value.startLocation.x / videoGeometry.size.width
                                                                            let currentX = value.location.x / videoGeometry.size.width
                                                                            playerViewModel.updateLineDragWithDelta(startX: startX, currentX: currentX)
                                                                        }
                                                                        .onEnded { _ in
                                                                            playerViewModel.endLineDrag()
                                                                        }
                                                                )

                                                                // Top handle - positioned at top edge
                                                                Circle()
                                                                    .fill(Color.red)
                                                                    .frame(width: 12, height: 12)
                                                                    .position(
                                                                        x: videoGeometry.size.width * playerViewModel.finishLineTopX,
                                                                        y: 0 // Top edge
                                                                    )
                                                                    .gesture(
                                                                        DragGesture()
                                                                            .onChanged { value in
                                                                                let newX = value.location.x / videoGeometry.size.width
                                                                                playerViewModel.setFinishLineTopX(newX)
                                                                            }
                                                                    )

                                                                // Bottom handle - positioned at bottom edge
                                                                Circle()
                                                                    .fill(Color.red)
                                                                    .frame(width: 12, height: 12)
                                                                    .position(
                                                                        x: videoGeometry.size.width * playerViewModel.finishLineBottomX,
                                                                        y: videoGeometry.size.height // Bottom edge
                                                                    )
                                                                    .gesture(
                                                                        DragGesture()
                                                                            .onChanged { value in
                                                                                let newX = value.location.x / videoGeometry.size.width
                                                                                playerViewModel.setFinishLineBottomX(newX)
                                                                            }
                                                                    )

                                                            }
                                                        }
                                                    }

                                                    // Virtual finish line — motion overlay (transparent CGImage above the video)
                                                    if playerViewModel.showMotionOverlay, let overlay = motionOverlayImage {
                                                        Image(decorative: overlay, scale: 1.0)
                                                            .resizable()
                                                            .interpolation(.none)
                                                            .aspectRatio(contentMode: .fit)
                                                            .allowsHitTesting(false)
                                                    }

                                                    // Detection segment handles — only when Motion Overlay is on
                                                    if playerViewModel.showMotionOverlay {
                                                        DetectionSegmentHandles(
                                                            topX: playerViewModel.finishLineTopX,
                                                            bottomX: playerViewModel.finishLineBottomX,
                                                            tStart: $motionTStart,
                                                            tEnd: $motionTEnd
                                                        )
                                                    }

                                                }
                                                .scaleEffect(playerViewModel.zoomScale)
                                                .offset(playerViewModel.zoomOffset)
                                                .frame(width: videoWidth, height: videoHeight)
                                                .clipped() // Clip zoomed content to frame bounds - disabled to debug
                                                .overlay(
                                                    Rectangle()
                                                        .stroke(Color.yellow, lineWidth: 1)
                                                )
                                                .onAppear {
                                                    if let url = captureManager.lastRecordedURL {
                                                        playerViewModel.loadVideo(url: url)
                                                    }
                                                }

                                            // Video controls overlay
                                            ZStack {
                                                // Zoom controls positioned to the right and vertically centered
                                                HStack {
                                                    Spacer()

                                                    // Zoom controls (right side) - vertically centered with video
                                                    VStack(spacing: 8) {
                                                        Text("ZOOM")
                                                            .foregroundColor(.white)
                                                            .font(.caption2)
                                                            .fontWeight(.semibold)

                                                        // Vertical zoom slider - made taller with tick marks
                                                        VStack(spacing: 4) {
                                                            Text("5x")
                                                                .foregroundColor(.white.opacity(0.7))
                                                                .font(.caption2)

                                                            ZStack {
                                                                // Tick marks for zoom levels
                                                                VStack(spacing: 0) {
                                                                    ForEach([5.0, 4.0, 3.0, 2.0, 1.0], id: \.self) { zoomLevel in
                                                                        HStack(spacing: 2) {
                                                                            Rectangle()
                                                                                .fill(Color.white.opacity(0.5))
                                                                                .frame(width: 8, height: 1)
                                                                            Text("\(Int(zoomLevel))x")
                                                                                .foregroundColor(.white.opacity(0.6))
                                                                                .font(.system(size: 8))
                                                                        }
                                                                        .frame(height: videoHeight * 0.12)
                                                                    }
                                                                }
                                                                .frame(width: 30, height: videoHeight * 0.6)

                                                                Slider(value: Binding(
                                                                    get: { playerViewModel.zoomScale },
                                                                    set: { playerViewModel.setZoom($0) }
                                                                ), in: 1.0...5.0, step: 0.1)
                                                                .accentColor(.white)
                                                                .frame(width: videoHeight * 0.6)
                                                                .rotationEffect(.degrees(-90))
                                                                .frame(width: 20, height: videoHeight * 0.6)
                                                            }

                                                            Text("1x")
                                                                .foregroundColor(.white.opacity(0.7))
                                                                .font(.caption2)
                                                        }

                                                        // 1x reset button
                                                        Button(action: { playerViewModel.resetZoom() }) {
                                                            Text("1x")
                                                                .foregroundColor(.white)
                                                                .font(.caption)
                                                                .fontWeight(.semibold)
                                                                .frame(width: 24, height: 20)
                                                                .background(Color.blue.opacity(0.8))
                                                                .cornerRadius(4)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Reset to 1x (⌘+0)")

                                                        // Current zoom display
                                                        Text(String(format: "%.1fx", playerViewModel.zoomScale))
                                                            .foregroundColor(.white)
                                                            .font(.caption2)
                                                    }
                                                    .padding(12)
                                                    .background(Color.black.opacity(0.7))
                                                    .cornerRadius(8)
                                                    .padding(.trailing, -50)
                                                }

                                            }

                                            // Show overlay when seeking outside video range
                                            if playerViewModel.isSeekingOutsideVideo {
                                                ZStack {
                                                    Color.black.opacity(0.8)
                                                        .cornerRadius(8)
                                                    VStack(spacing: 10) {
                                                        Image(systemName: "video.slash")
                                                            .font(.system(size: 40))
                                                            .foregroundColor(.white)
                                                        Text("No video")
                                                            .font(.headline)
                                                            .foregroundColor(.white)
                                                        Text("Outside recording range")
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                    }
                                                }
                                                .frame(width: videoWidth, height: videoHeight)
                                            }
                                        }
                                        }
                                        .frame(width: outerGeometry.size.width * 0.9, height: outerGeometry.size.height * 0.9)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                }
                                .frame(maxHeight: .infinity)
                            }
                        }

                        // Empty state when no camera or video
                        if (captureManager.captureSession == nil || (!timingModel.isRaceActive && timingModel.raceStartTime != nil)) &&
                           (timingModel.isRaceActive || captureManager.lastRecordedURL == nil) {
                            VStack {
                                Spacer()
                                Image(systemName: "video.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("Select a camera to begin")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.windowBackgroundColor))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Spacer().frame(height: 10)

                // Add flexible space between video and timeline
                Spacer()

                // Show race timeline only in review mode
                if isReviewMode {
                    RaceTimelineView(
                        timingModel: timingModel,
                        captureManager: captureManager,
                        playerViewModel: playerViewModel,
                        triggerLaneSelection: $triggerLaneSelection,
                        onDataChanged: markTimelineDataAsUnsaved
                    )
                    .frame(height: playerViewModel.motionSweepRows.isEmpty ? 300 : 350)
                    .padding(.horizontal)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .alert("Export Complete", isPresented: $showExportSuccess) {
            Button("OK") { }
        } message: {
            Text("Frame exported successfully")
        }
        .sheet(isPresented: $showMotionSweepSheet) {
            if let url = recordedVideoURL ?? captureManager.lastRecordedURL {
                MotionSweepSheet(
                    videoURL: url,
                    p1: CGPoint(x: playerViewModel.finishLineTopX, y: 0),
                    p2: CGPoint(x: playerViewModel.finishLineBottomX, y: 1),
                    roiHalfWidthPx: motionRoiHalfWidthPx,
                    tStart: motionTStart,
                    tEnd: motionTEnd,
                    initialThreshold: playerViewModel.motionThreshold,
                    initialRows: playerViewModel.motionSweepRows,
                    initialCrossings: playerViewModel.motionCrossings,
                    onSeek: { t in
                        playerViewModel.seek(to: t, precise: true)
                    },
                    onSweepCompleted: { rows, crossings in
                        playerViewModel.motionSweepRows = rows
                        playerViewModel.motionCrossings = crossings
                    },
                    onClose: { showMotionSweepSheet = false }
                )
            } else {
                VStack(spacing: 12) {
                    Text("Cannot run sweep")
                    Text("A recorded video is required.")
                        .font(.caption).foregroundColor(.secondary)
                    Button("Close") { showMotionSweepSheet = false }
                }
                .padding(20)
            }
        }
        .onChange(of: playerViewModel.currentTime) { _ in scheduleMotionOverlayRefresh() }
        .onChange(of: playerViewModel.showMotionOverlay) { on in
            if on { scheduleMotionOverlayRefresh() } else { motionOverlayImage = nil }
        }
        .onChange(of: playerViewModel.motionThreshold) { _ in
            if playerViewModel.showMotionOverlay { scheduleMotionOverlayRefresh() }
        }
        .onChange(of: motionRoiHalfWidthPx) { _ in
            if playerViewModel.showMotionOverlay { scheduleMotionOverlayRefresh() }
        }
        .onChange(of: playerViewModel.finishLineTopX) { _ in
            if playerViewModel.showMotionOverlay { scheduleMotionOverlayRefresh() }
        }
        .onChange(of: playerViewModel.finishLineBottomX) { _ in
            if playerViewModel.showMotionOverlay { scheduleMotionOverlayRefresh() }
        }
        .onChange(of: motionTStart) { _ in
            if playerViewModel.showMotionOverlay { scheduleMotionOverlayRefresh() }
        }
        .onChange(of: motionTEnd) { _ in
            if playerViewModel.showMotionOverlay { scheduleMotionOverlayRefresh() }
        }
        .onAppear {
            captureManager.checkPermissions()
            captureManager.timingModel = timingModel
            playerViewModel.timingModel = timingModel
            timingModel.outputDirectory = captureManager.outputDirectory

            // Set up keyboard monitoring
            setupKeyboardMonitoring()

            // First refresh devices, then wait for them to be loaded
            captureManager.refreshDevices()

            // Device auto-selection is now handled by CaptureManager
        }
        .onDisappear {
            // Clean up keyboard monitoring
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    private func toggleRecording() {
        // This function is no longer used - recording is controlled by timing panel
    }


    private func exportCurrentFrame() {
        guard let videoURL = recordedVideoURL,
              let outputFolder = outputFolderURL else { return }

        isExporting = true

        let exporter = FrameExporter()
        let currentTime = playerViewModel.currentTime
        let outputURL = outputFolder.appendingPathComponent("frame_\(Int(currentTime * 1000))ms.jpg")

        exporter.exportFrame(from: videoURL, at: currentTime, to: outputURL, zeroTolerance: true) { success in
            DispatchQueue.main.async {
                isExporting = false
                showExportSuccess = success
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }

    private func formatRaceTime(_ videoTime: Double) -> String {
        // Convert video time to race time
        if let raceTime = timingModel.raceTimeForVideoTime(videoTime) {
            let minutes = Int(raceTime) / 60
            let secs = Int(raceTime) % 60
            let millis = Int((raceTime.truncatingRemainder(dividingBy: 1)) * 1000)
            return String(format: "%02d:%02d.%03d", minutes, secs, millis)
        } else {
            return "Before race start"
        }
    }

    // MARK: - Motion Overlay (Phase A virtual finish line)

    private func barColor(for frac: Double) -> Color {
        // 0..0.33 = blue (no signal), 0.33..0.66 = yellow, 0.66..1 = red (strong fire)
        if frac < 0.05 { return Color.gray.opacity(0.5) }
        if frac < 0.33 { return Color.cyan }
        if frac < 0.66 { return Color.yellow }
        return Color.red
    }


    private func scheduleMotionOverlayRefresh() {
        guard playerViewModel.showMotionOverlay,
              (recordedVideoURL ?? captureManager.lastRecordedURL) != nil else {
            return
        }
        motionOverlayTask?.cancel()
        motionOverlayTask = Task {
            // Debounce — coalesce rapid scrub updates.
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
            await refreshMotionOverlay()
        }
    }

    private func refreshMotionOverlay() async {
        guard let url = recordedVideoURL ?? captureManager.lastRecordedURL else { return }
        let t = playerViewModel.currentTime
        let threshold = playerViewModel.motionThreshold
        let p1 = CGPoint(x: playerViewModel.finishLineTopX, y: 0)
        let p2 = CGPoint(x: playerViewModel.finishLineBottomX, y: 1)
        let roi = motionRoiHalfWidthPx
        let tStart = motionTStart
        let tEnd = motionTEnd
        let result: MotionAnalysisResult? = await Task.detached(priority: .userInitiated) {
            let asset = AVAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            gen.appliesPreferredTrackTransform = true
            let curT = CMTime(seconds: max(0, t), preferredTimescale: 600)
            guard let cur = try? gen.copyCGImage(at: curT, actualTime: nil) else { return nil }
            var baselines: [CGImage] = []
            for d in MotionInspector.defaultBaselineDeltas {
                let bt = CMTime(seconds: max(0, t + d), preferredTimescale: 600)
                if let b = try? gen.copyCGImage(at: bt, actualTime: nil) {
                    baselines.append(b)
                }
            }
            guard !baselines.isEmpty else { return nil }
            return MotionInspector.motionAnalysis(
                currentFrame: cur, baselines: baselines,
                normalizedP1: p1, normalizedP2: p2,
                roiHalfWidthPx: roi, threshold: threshold,
                tStart: tStart, tEnd: tEnd
            )
        }.value
        if Task.isCancelled { return }
        await MainActor.run {
            self.motionOverlayImage = result?.overlay
            let e = result?.energy ?? 0
            self.motionEnergy = e
            self.motionCentroid = result?.centroidOffsetAlongLine ?? 0
            if e > self.motionMaxRecent { self.motionMaxRecent = e }
        }
    }

    private func loadLastClip() {
        if let lastURL = captureManager.lastRecordedURL {
            recordedVideoURL = lastURL
            playerViewModel.loadVideo(url: lastURL)

            // Try to find a session file (either RaceName.json or session.json)
            let directory = lastURL.deletingLastPathComponent()
            let fileManager = FileManager.default
            if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                // Look for any .json file
                if let jsonFile = files.first(where: { $0.pathExtension == "json" }) {
                    timingModel.loadSession(from: jsonFile)
                    syncToRaceTime = timingModel.raceStartTime != nil
                }
            }
        }
    }

    // MARK: - Keyboard Shortcuts
    private func setupKeyboardMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return self.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Diagnostic: log every key press the monitor sees, with first-responder class.
        if keyCode == 123 || keyCode == 124 {
            let frClass = (NSApp.keyWindow?.firstResponder).map { String(describing: type(of: $0)) } ?? "nil"
            print("⌨️ ArrowKey monitor: code=\(keyCode) firstResponder=\(frClass) isTextFieldEditing=\(isTextFieldEditing())")
        }

        // Handle special keys first
        switch keyCode {
        case 49: // SPACE
            handleRecordShortcut()
            return nil // Consume the event

        case 36: // RETURN
            // Don't handle start/stop if a text field is being edited
            if !isTextFieldEditing() {
                handleStartStopShortcut()
                return nil
            }
            return event // Let the text field handle it

        case 53: // ESCAPE
            // Don't handle emergency stop if a text field is being edited
            if !isTextFieldEditing() {
                handleEmergencyStopShortcut()
                return nil
            }
            return event // Let the text field handle it

        case 123: // LEFT ARROW
            // Don't handle timeline navigation if a text field is being edited
            if !isTextFieldEditing() {
                handleTimelineNavigation(direction: .left, modifiers: modifierFlags)
                return nil
            }
            return event // Let the text field handle it

        case 124: // RIGHT ARROW
            // Don't handle timeline navigation if a text field is being edited
            if !isTextFieldEditing() {
                handleTimelineNavigation(direction: .right, modifiers: modifierFlags)
                return nil
            }
            return event // Let the text field handle it

        case 115: // HOME
            handleTimelineJump(.start)
            return nil

        case 119: // END
            handleTimelineJump(.end)
            return nil


        default:
            break
        }

        // Handle character-based shortcuts
        switch characters {
        case "m":
            handleOpenLaneSelectionShortcut()
            return nil

        case "f":
            handlePhotoFinishShortcut()
            return nil

        case "[":
            // Alternate timeline-back shortcut (in case arrow keys are intercepted)
            if !isTextFieldEditing() {
                handleTimelineNavigation(direction: .left, modifiers: modifierFlags)
                return nil
            }
            return event

        case "]":
            // Alternate timeline-forward shortcut
            if !isTextFieldEditing() {
                handleTimelineNavigation(direction: .right, modifiers: modifierFlags)
                return nil
            }
            return event

        case "e" where modifierFlags.contains(.command):
            handleExportShortcut()
            return nil

        case "s" where modifierFlags.contains(.command):
            handleSaveShortcut()
            return nil

        case "=" where modifierFlags.contains(.command), "+" where modifierFlags.contains(.command):
            playerViewModel.zoomIn()
            return nil

        case "-" where modifierFlags.contains(.command):
            playerViewModel.zoomOut()
            return nil

        case "0" where modifierFlags.contains(.command):
            playerViewModel.resetZoom()
            return nil


        default:
            break
        }

        // Don't consume the event if we didn't handle it
        return event
    }

    // MARK: - Shortcut Handlers

    private func handleRecordShortcut() {
        // Only allow recording during active race, not after race is completed
        // Also disable in review mode
        guard timingModel.isRaceActive,
              !isReviewMode else { return }

        // Delegate to RaceTimingPanel's record handling
        if captureManager.selectedDevice != nil &&
           timingModel.isRaceInitialized {

            if captureManager.isRecording {
                captureManager.stopRecording { _ in
                    print("Stopped video recording via shortcut")
                    // Mark as unsaved when recording stops
                    self.markTimelineDataAsUnsaved()
                }
            } else {
                // Pass nil so CaptureManager routes to the Event/Free Races folder
                // based on session type (so video lands alongside JSON and images).
                captureManager.startRecording(to: nil) { success in
                    if success {
                        print("Started video recording via shortcut")
                        // Mark as unsaved when recording starts
                        self.markTimelineDataAsUnsaved()
                    }
                }
            }
        }
    }

    private func handleStartStopShortcut() {
        // Only allow during race setup (before race starts), not during or after race
        // Also disable in review mode
        guard timingModel.raceStartTime == nil,
              timingModel.isRaceInitialized,
              !isReviewMode else { return }

        // Start race (only if race hasn't started yet)
        timingModel.startRace()
    }

    private func handleEmergencyStopShortcut() {
        // Only allow emergency stop during active race
        // Also disable in review mode
        guard timingModel.isRaceActive,
              !isReviewMode else { return }

        // Emergency stop - stop both race and recording immediately
        timingModel.stopRace()
        if captureManager.isRecording {
            captureManager.stopRecording { url in
                print("Stopped race and recording via ESC key")
                // Save video path if available
                if let videoURL = url {
                    timingModel.sessionData?.videoFilePath = videoURL.path
                    // Mark as unsaved when video is saved
                    self.markTimelineDataAsUnsaved()
                }

                // Auto-switch to Review mode after stopping race
                DispatchQueue.main.async {
                    print("🎬 Auto-switching to Review mode after ESC stop")
                    self.isReviewMode = true
                }
            }
        } else {
            // No recording was active, still switch to review mode
            print("🎬 Auto-switching to Review mode after ESC stop (no recording)")
            isReviewMode = true
        }
    }

    private enum TimelineDirection {
        case left, right
    }

    private func isTextFieldEditing() -> Bool {
        // Check if the current first responder is a text field
        guard let keyWindow = NSApp.keyWindow,
              let firstResponder = keyWindow.firstResponder else {
            return false
        }

        // Check if it's an NSTextField or NSTextView (text editing)
        return firstResponder is NSTextField || firstResponder is NSTextView
    }

    private enum TimelineJump {
        case start, end
    }

    /// Returns the current video's frame duration (seconds per frame).
    /// Falls back to 1/30s if the rate cannot be determined.
    private func videoFrameDuration() -> Double {
        guard let asset = playerViewModel.player.currentItem?.asset else {
            return 1.0 / 30.0
        }
        let tracks = asset.tracks(withMediaType: .video)
        guard let track = tracks.first else {
            return 1.0 / 30.0
        }
        let fps = Double(track.nominalFrameRate)
        return fps > 0 ? 1.0 / fps : 1.0 / 30.0
    }

    private func handleTimelineNavigation(direction: TimelineDirection, modifiers: NSEvent.ModifierFlags) {
        // Only work when race is completed (not active, has started, and has been stopped)
        guard !timingModel.isRaceActive,
              timingModel.raceStartTime != nil,
              captureManager.lastRecordedURL != nil,
              playerViewModel.player.currentItem != nil else { return }

        let currentTime = playerViewModel.currentTime
        let frameDuration = videoFrameDuration()
        // Single step = 1 frame, regardless of modifiers.
        var newTime = direction == .left ? currentTime - frameDuration : currentTime + frameDuration

        // Clamp to video bounds
        if let duration = playerViewModel.player.currentItem?.duration,
           CMTIME_IS_VALID(duration) {
            let maxTime = CMTimeGetSeconds(duration)
            newTime = max(0, min(newTime, maxTime))
        } else {
            newTime = max(0, newTime)
        }

        // Frame-accurate seek (zero tolerance) so frame stepping lands on real frames,
        // not interpolated keyframe approximations.
        let seekTime = CMTime(seconds: newTime, preferredTimescale: 6000)
        playerViewModel.player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        playerViewModel.currentTime = newTime

        // Defensive: AVPlayerView's underlying NSView may grab first-responder after
        // a seek and start swallowing arrow keys for its own frame-step behavior.
        // Clear first responder so subsequent arrow events reach our local monitor cleanly.
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                let fr = window.firstResponder
                // Only reset if a non-textfield view holds focus — don't steal from text editing.
                if !(fr is NSTextField) && !(fr is NSTextView) {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    private func handleTimelineJump(_ jump: TimelineJump) {
        // Only work when race is completed (not active, has started, and has been stopped)
        guard !timingModel.isRaceActive,
              timingModel.raceStartTime != nil,
              captureManager.lastRecordedURL != nil,
              let duration = playerViewModel.player.currentItem?.duration,
              CMTIME_IS_VALID(duration) else { return }

        let seekTime: CMTime
        switch jump {
        case .start:
            seekTime = CMTime.zero
        case .end:
            seekTime = duration
        }

        playerViewModel.player.seek(to: seekTime)
        playerViewModel.currentTime = CMTimeGetSeconds(seekTime)
    }

    private func handleOpenLaneSelectionShortcut() {
        // Only work when race is completed (not active, has started, and has been stopped)
        guard !timingModel.isRaceActive,
              timingModel.raceStartTime != nil else { return }

        // Trigger the lane selection dialog in RaceTimelineView
        triggerLaneSelection = true
    }

    private func handlePhotoFinishShortcut() {
        // Only work when race is completed (not active, has started, and has been stopped)
        guard !timingModel.isRaceActive,
              timingModel.raceStartTime != nil,
              captureManager.lastRecordedURL != nil,
              playerViewModel.player.currentItem != nil else { return }

        // Toggle photo finish overlay
        playerViewModel.togglePhotoFinishOverlay()
    }

    private func handleAddFinishShortcut() {
        // This function is no longer used since M key now opens lane selection dialog
        // The functionality is now handled through the RaceTimelineView dialog
        print("handleAddFinishShortcut called - this should not happen")
    }




    private func handleExportShortcut() {
        // Only export when race is completed and we have a frame to export
        guard !timingModel.isRaceActive,
              timingModel.raceStartTime != nil,
              captureManager.lastRecordedURL != nil,
              playerViewModel.player.currentItem != nil else { return }

        // Use existing export functionality
        exportCurrentFrame()
    }

    private func handleSaveShortcut() {
        // Save current session
        timingModel.saveCurrentSession()
        print("Session saved via shortcut")
    }
}



// MARK: - Detection Segment Handles
//
// Two draggable green handles overlaid on the existing yellow finish line that
// define which sub-segment of the line is used for motion analysis. The handles
// snap to the line itself (interpolating between top/bottom endpoints), so
// dragging only adjusts t in [0, 1] along the line — not perpendicular position.
struct DetectionSegmentHandles: View {
    let topX: Double          // PlayerViewModel.finishLineTopX (normalized 0..1)
    let bottomX: Double       // PlayerViewModel.finishLineBottomX (normalized 0..1)
    @Binding var tStart: Double  // 0..1, top of analyzed segment
    @Binding var tEnd: Double    // 0..1, bottom of analyzed segment

    var body: some View {
        GeometryReader { geo in
            let p1 = CGPoint(x: topX * geo.size.width, y: 0)
            let p2 = CGPoint(x: bottomX * geo.size.width, y: geo.size.height)

            // Highlight the analyzed segment with a thicker green stroke.
            let segStart = lerp(p1, p2, t: tStart)
            let segEnd   = lerp(p1, p2, t: tEnd)
            ZStack {
                Path { p in
                    p.move(to: segStart)
                    p.addLine(to: segEnd)
                }
                .stroke(Color.green.opacity(0.55), lineWidth: 4)
                .allowsHitTesting(false)

                // Top (start) handle
                handleCircle(at: segStart)
                    .gesture(dragGesture(geoSize: geo.size, isStart: true))
                Text(String(format: "%.0f%%", tStart * 100))
                    .font(.system(size: 10).bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.black.opacity(0.6)).cornerRadius(3)
                    .position(x: segStart.x + 26, y: segStart.y)
                    .allowsHitTesting(false)

                // Bottom (end) handle
                handleCircle(at: segEnd)
                    .gesture(dragGesture(geoSize: geo.size, isStart: false))
                Text(String(format: "%.0f%%", tEnd * 100))
                    .font(.system(size: 10).bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.black.opacity(0.6)).cornerRadius(3)
                    .position(x: segEnd.x + 26, y: segEnd.y)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handleCircle(at point: CGPoint) -> some View {
        Circle()
            .fill(Color.green)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: 16, height: 16)
            .shadow(radius: 2)
            .position(point)
    }

    /// Project a screen-space point onto the finish line and return its parametric t.
    private func projectToLine(_ point: CGPoint, p1: CGPoint, p2: CGPoint) -> Double {
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0.0001 else { return 0 }
        let t = ((point.x - p1.x) * dx + (point.y - p1.y) * dy) / lenSq
        return max(0, min(1, Double(t)))
    }

    private func dragGesture(geoSize: CGSize, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p1 = CGPoint(x: topX * geoSize.width, y: 0)
                let p2 = CGPoint(x: bottomX * geoSize.width, y: geoSize.height)
                let t = projectToLine(value.location, p1: p1, p2: p2)
                if isStart {
                    tStart = min(t, tEnd - 0.02)
                } else {
                    tEnd = max(t, tStart + 0.02)
                }
            }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
    }
}
