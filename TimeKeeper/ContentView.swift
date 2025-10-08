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
}

struct ContentView: View {
    @StateObject private var captureManager = CaptureManager()
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

    var body: some View {
        HStack(spacing: 0) {
            // Left side - Controls
            VStack(alignment: .leading, spacing: 0) {
                RaceTimingPanel(timingModel: timingModel, captureManager: captureManager, playerViewModel: playerViewModel, isReviewMode: $isReviewMode)
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
                                Text("Recorded Video")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                        triggerLaneSelection: $triggerLaneSelection
                    )
                    .frame(height: 300)
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
                }
            } else {
                captureManager.startRecording(to: captureManager.outputDirectory) { success in
                    if success {
                        print("Started video recording via shortcut")
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
            captureManager.stopRecording { _ in
                print("Stopped race and recording via ESC key")
            }
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

    private func handleTimelineNavigation(direction: TimelineDirection, modifiers: NSEvent.ModifierFlags) {
        // Only work when race is completed (not active, has started, and has been stopped)
        guard !timingModel.isRaceActive,
              timingModel.raceStartTime != nil,
              captureManager.lastRecordedURL != nil,
              playerViewModel.player.currentItem != nil else { return }

        let currentTime = playerViewModel.currentTime
        var newTime: Double

        if modifiers.contains(.shift) {
            // Fine adjustment: ±1ms
            newTime = direction == .left ? currentTime - 0.001 : currentTime + 0.001
        } else if modifiers.contains(.command) {
            // Coarse adjustment: ±100ms
            newTime = direction == .left ? currentTime - 0.1 : currentTime + 0.1
        } else {
            // Normal adjustment: ±10ms
            newTime = direction == .left ? currentTime - 0.01 : currentTime + 0.01
        }

        // Clamp to video bounds
        if let duration = playerViewModel.player.currentItem?.duration,
           CMTIME_IS_VALID(duration) {
            let maxTime = CMTimeGetSeconds(duration)
            newTime = max(0, min(newTime, maxTime))
        } else {
            newTime = max(0, newTime)
        }

        // Seek to new time
        let seekTime = CMTime(seconds: newTime, preferredTimescale: 1000)
        playerViewModel.player.seek(to: seekTime)
        playerViewModel.currentTime = newTime
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
