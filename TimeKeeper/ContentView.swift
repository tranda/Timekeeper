import SwiftUI
import AVKit
import UniformTypeIdentifiers
import Combine

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

    var body: some View {
        HStack(spacing: 0) {
            // Left side - Controls
            VStack(alignment: .leading, spacing: 20) {
                RaceTimingPanel(timingModel: timingModel, captureManager: captureManager, playerViewModel: playerViewModel)

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

                // Keyboard shortcuts help
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyboard Shortcuts")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        // Show ENTER only before race starts
                        if timingModel.raceStartTime == nil && timingModel.isRaceInitialized {
                            HStack {
                                Text("ENTER")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                Text("Start Race")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Show SPACE and ESC only during active race
                        if timingModel.isRaceActive {
                            HStack {
                                Text("SPACE")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                Text("Record")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("ESC")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                Text("Stop Race")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if !timingModel.isRaceActive && timingModel.raceStartTime != nil {
                            HStack {
                                Text("M")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                Text("Add Marker")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("←→")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                Text("Navigate ±10ms")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
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
                        // Show camera preview only when race is active or not yet started
                        if captureManager.captureSession != nil && (timingModel.isRaceActive || timingModel.raceStartTime == nil) {
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

                        // Show recorded video player when we have a recording to review
                        if !timingModel.isRaceActive && captureManager.lastRecordedURL != nil {
                            VStack(spacing: 5) {
                                Text("Recorded Video")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                GeometryReader { geometry in
                                    // Landscape video (16:9 aspect ratio) - match live preview format
                                    let maxWidth = min(geometry.size.width * 0.9, 800)
                                    let videoHeight = maxWidth * (9.0 / 16.0)
                                    let videoWidth = maxWidth

                                    HStack {
                                        Spacer()
                                        ZStack {
                                            VideoPlayer(player: playerViewModel.player)
                                                .frame(width: videoWidth, height: videoHeight)
                                                .background(Color.black)
                                                .aspectRatio(contentMode: .fit)  // Show full video with letterboxing
                                                .cornerRadius(8)
                                                .onAppear {
                                                    if let url = captureManager.lastRecordedURL {
                                                        playerViewModel.loadVideo(url: url)
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

                // Show race timeline after race is stopped (in fixed height area)
                if !timingModel.isRaceActive && timingModel.raceStartTime != nil {
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
            handleStartStopShortcut()
            return nil

        case 53: // ESCAPE
            handleEmergencyStopShortcut()
            return nil

        case 123: // LEFT ARROW
            handleTimelineNavigation(direction: .left, modifiers: modifierFlags)
            return nil

        case 124: // RIGHT ARROW
            handleTimelineNavigation(direction: .right, modifiers: modifierFlags)
            return nil

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


        case "e" where modifierFlags.contains(.command):
            handleExportShortcut()
            return nil

        case "s" where modifierFlags.contains(.command):
            handleSaveShortcut()
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
        guard timingModel.isRaceActive else { return }

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
        guard timingModel.raceStartTime == nil,
              timingModel.isRaceInitialized else { return }

        // Start race (only if race hasn't started yet)
        timingModel.startRace()
    }

    private func handleEmergencyStopShortcut() {
        // Only allow emergency stop during active race
        guard timingModel.isRaceActive else { return }

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