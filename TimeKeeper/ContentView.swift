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
    @State private var selectedDeviceID: String?
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
            VStack(alignment: .leading, spacing: 20) {
                RaceTimingPanel(timingModel: timingModel, captureManager: captureManager, playerViewModel: playerViewModel, isReviewMode: $isReviewMode)

                Divider()

                // Camera and Output in compact horizontal layout
                HStack(spacing: 20) {
                    // Camera selection
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Camera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $selectedDeviceID) {
                            Text("None").tag(nil as String?)
                            ForEach(captureManager.availableDevices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID as String?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: selectedDeviceID) { newDeviceID in
                            if let deviceID = newDeviceID,
                               let device = captureManager.availableDevices.first(where: { $0.uniqueID == deviceID }) {
                                // Stop current session before switching
                                if captureManager.isSessionRunning {
                                    captureManager.stopSession()
                                }

                                // Small delay to ensure clean switch
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    captureManager.selectDevice(device)
                                }
                            }
                        }
                    }

                    // Output folder
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Output Folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Text(captureManager.outputDirectory?.lastPathComponent ?? "Desktop")
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .frame(width: 180, alignment: .leading)
                            Button("Choose") {
                                selectOutputFolder()
                            }
                            .font(.system(size: 12))
                        }
                    }

                    Spacer()
                }

                Spacer()
            }
            .frame(minWidth: 600, idealWidth: 700, maxWidth: 800)
            .padding()

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
                                            Spacer()
                                            // Container view that's 90% of parent size
                                            GeometryReader { geometry in
                                            let videoWidth = geometry.size.width
                                            let videoHeight = geometry.size.height

                                            ZStack {
                                            AVPlayerView(player: playerViewModel.player)
                                                .frame(width: videoWidth, height: videoHeight)
                                                .background(Color.black)
                                                .aspectRatio(contentMode: .fit)  // Show full video with letterboxing
                                                .cornerRadius(8)
                                                .focusable(false)  // Disable keyboard focus and shortcuts
                                                .scaleEffect(playerViewModel.zoomScale)
                                                .offset(playerViewModel.zoomOffset)
                                                .clipped() // Clip zoomed content to frame bounds
                                                .gesture(
                                                    SimultaneousGesture(
                                                        MagnificationGesture()
                                                            .onChanged { scale in
                                                                playerViewModel.setZoom(scale)
                                                            },
                                                        DragGesture()
                                                            .onChanged { value in
                                                                if playerViewModel.zoomScale > 1.0 {
                                                                    playerViewModel.panVideo(by: CGSize(
                                                                        width: value.translation.width * 0.5,
                                                                        height: value.translation.height * 0.5
                                                                    ))
                                                                }
                                                            }
                                                    )
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
                                                                        .frame(height: videoHeight / 5)
                                                                    }
                                                                }
                                                                .frame(width: 30, height: videoHeight)

                                                                Slider(value: Binding(
                                                                    get: { playerViewModel.zoomScale },
                                                                    set: { playerViewModel.setZoom($0) }
                                                                ), in: 1.0...5.0, step: 0.1)
                                                                .accentColor(.white)
                                                                .frame(width: videoHeight)
                                                                .rotationEffect(.degrees(-90))
                                                                .frame(width: 20, height: videoHeight)
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

                                                // Pan controls positioned at bottom center
                                                VStack {
                                                    Spacer()
                                                    Spacer()
                                                // Pan controls (pushed down more) - only show when zoomed
                                                if playerViewModel.zoomScale > 1.0 {
                                                    HStack {
                                                        Spacer()

                                                        VStack(spacing: 8) {
                                                            Text("PAN")
                                                                .foregroundColor(.white)
                                                                .font(.caption2)
                                                                .fontWeight(.semibold)

                                                            VStack(spacing: 6) {
                                                                // Up arrow
                                                                Button(action: {
                                                                    if !playerViewModel.isPanningLongerThanThreshold {
                                                                        playerViewModel.panVideo(by: CGSize(width: 0, height: -20))
                                                                    }
                                                                }) {
                                                                    Image(systemName: "chevron.up")
                                                                        .foregroundColor(.white)
                                                                        .font(.body)
                                                                        .frame(width: 32, height: 24)
                                                                        .background(Color.gray.opacity(0.3))
                                                                        .cornerRadius(4)
                                                                }
                                                                .buttonStyle(.plain)
                                                                .help("Pan Up (Hold for continuous)")
                                                                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 10) {
                                                                    // This fires when long press is detected
                                                                } onPressingChanged: { pressing in
                                                                    if pressing {
                                                                        playerViewModel.startContinuousPan(direction: CGSize(width: 0, height: -5))
                                                                    } else {
                                                                        playerViewModel.stopContinuousPan()
                                                                    }
                                                                }

                                                                HStack(spacing: 6) {
                                                                    // Left arrow
                                                                    Button(action: {
                                                                        if !playerViewModel.isPanningLongerThanThreshold {
                                                                            playerViewModel.panVideo(by: CGSize(width: -20, height: 0))
                                                                        }
                                                                    }) {
                                                                        Image(systemName: "chevron.left")
                                                                            .foregroundColor(.white)
                                                                            .font(.body)
                                                                            .frame(width: 24, height: 32)
                                                                            .background(Color.gray.opacity(0.3))
                                                                            .cornerRadius(4)
                                                                    }
                                                                    .buttonStyle(.plain)
                                                                    .help("Pan Left (Hold for continuous)")
                                                                    .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 10) {
                                                                        // This fires when long press is detected
                                                                    } onPressingChanged: { pressing in
                                                                        if pressing {
                                                                            playerViewModel.startContinuousPan(direction: CGSize(width: -5, height: 0))
                                                                        } else {
                                                                            playerViewModel.stopContinuousPan()
                                                                        }
                                                                    }

                                                                    // Center/reset pan button
                                                                    Button(action: { playerViewModel.zoomOffset = .zero }) {
                                                                        Image(systemName: "dot.circle")
                                                                            .foregroundColor(.white)
                                                                            .font(.body)
                                                                            .frame(width: 24, height: 24)
                                                                            .background(Color.blue.opacity(0.6))
                                                                            .cornerRadius(4)
                                                                    }
                                                                    .buttonStyle(.plain)
                                                                    .help("Center View")

                                                                    // Right arrow
                                                                    Button(action: {
                                                                        if !playerViewModel.isPanningLongerThanThreshold {
                                                                            playerViewModel.panVideo(by: CGSize(width: 20, height: 0))
                                                                        }
                                                                    }) {
                                                                        Image(systemName: "chevron.right")
                                                                            .foregroundColor(.white)
                                                                            .font(.body)
                                                                            .frame(width: 24, height: 32)
                                                                            .background(Color.gray.opacity(0.3))
                                                                            .cornerRadius(4)
                                                                    }
                                                                    .buttonStyle(.plain)
                                                                    .help("Pan Right (Hold for continuous)")
                                                                    .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 10) {
                                                                        // This fires when long press is detected
                                                                    } onPressingChanged: { pressing in
                                                                        if pressing {
                                                                            playerViewModel.startContinuousPan(direction: CGSize(width: 5, height: 0))
                                                                        } else {
                                                                            playerViewModel.stopContinuousPan()
                                                                        }
                                                                    }
                                                                }

                                                                // Down arrow
                                                                Button(action: {
                                                                    if !playerViewModel.isPanningLongerThanThreshold {
                                                                        playerViewModel.panVideo(by: CGSize(width: 0, height: 20))
                                                                    }
                                                                }) {
                                                                    Image(systemName: "chevron.down")
                                                                        .foregroundColor(.white)
                                                                        .font(.body)
                                                                        .frame(width: 32, height: 24)
                                                                        .background(Color.gray.opacity(0.3))
                                                                        .cornerRadius(4)
                                                                }
                                                                .buttonStyle(.plain)
                                                                .help("Pan Down (Hold for continuous)")
                                                                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 10) {
                                                                    // This fires when long press is detected
                                                                } onPressingChanged: { pressing in
                                                                    if pressing {
                                                                        playerViewModel.startContinuousPan(direction: CGSize(width: 0, height: 5))
                                                                    } else {
                                                                        playerViewModel.stopContinuousPan()
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        .padding(8)
                                                        .background(Color.black.opacity(0.7))
                                                        .cornerRadius(8)

                                                        Spacer()
                                                    }
                                                    .padding(.bottom, -50)
                                                }
                                                }
                                            }

                                            // Photo finish overlay
                                            if playerViewModel.showPhotoFinishOverlay {
                                                GeometryReader { geometry in
                                                    ZStack {
                                                        // Finish line - slightly smaller than video frame
                                                        Path { path in
                                                            let margin = geometry.size.height * 0.1 // 10% margin
                                                            let topX = geometry.size.width * playerViewModel.finishLineTopX
                                                            let topY: CGFloat = margin // 10% from top
                                                            let bottomX = geometry.size.width * playerViewModel.finishLineBottomX
                                                            let bottomY = geometry.size.height - margin // 10% from bottom

                                                            path.move(to: CGPoint(x: topX, y: topY))
                                                            path.addLine(to: CGPoint(x: bottomX, y: bottomY))
                                                        }
                                                        .stroke(Color.red, lineWidth: 3)
                                                        .gesture(
                                                            DragGesture()
                                                                .onChanged { value in
                                                                    let deltaX = value.translation.width / geometry.size.width
                                                                    playerViewModel.moveFinishLineHorizontally(by: deltaX * 0.01)
                                                                }
                                                        )

                                                        // Top handle - positioned at top end of shortened line
                                                        Circle()
                                                            .fill(Color.red)
                                                            .frame(width: 12, height: 12)
                                                            .position(
                                                                x: geometry.size.width * playerViewModel.finishLineTopX,
                                                                y: geometry.size.height * 0.1 // 10% from top
                                                            )
                                                            .gesture(
                                                                DragGesture()
                                                                    .onChanged { value in
                                                                        let newX = value.location.x / geometry.size.width
                                                                        playerViewModel.setFinishLineTopX(newX)
                                                                    }
                                                            )

                                                        // Bottom handle - positioned at bottom end of shortened line
                                                        Circle()
                                                            .fill(Color.red)
                                                            .frame(width: 12, height: 12)
                                                            .position(
                                                                x: geometry.size.width * playerViewModel.finishLineBottomX,
                                                                y: geometry.size.height * 0.9 // 10% from bottom
                                                            )
                                                            .gesture(
                                                                DragGesture()
                                                                    .onChanged { value in
                                                                        let newX = value.location.x / geometry.size.width
                                                                        playerViewModel.setFinishLineBottomX(newX)
                                                                    }
                                                            )

                                                        // Debug quad at bottom left of VideoPlayer frame
                                                        // TODO: Re-enable for debugging coordinate alignment
                                                        // Rectangle()
                                                        //     .fill(Color.green)
                                                        //     .frame(width: 20, height: 20)
                                                        //     .position(
                                                        //         x: 10, // 10px from left edge
                                                        //         y: videoHeight - 10 // 10px from bottom of video area
                                                        //     )

                                                    }
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
                Spacer().frame(height: 100)

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

            // Give more time for device enumeration to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Create a local copy of devices to avoid mutation issues
                let devices = captureManager.availableDevices

                // Try to find and select the back camera first
                let backCamera = devices.first { device in
                    // Check for back camera indicators in the device name
                    let name = device.localizedName.lowercased()
                    return name.contains("back") ||
                           name.contains("rear") ||
                           (name.contains("iphone") && !name.contains("front"))
                }

                // Use back camera if found, otherwise use first available
                if let preferredDevice = backCamera ?? devices.first {
                    selectedDeviceID = preferredDevice.uniqueID
                    captureManager.selectDevice(preferredDevice)
                }
            }
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

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"

        if panel.runModal() == .OK {
            outputFolderURL = panel.url
            captureManager.outputDirectory = panel.url
            timingModel.outputDirectory = panel.url
        }
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
