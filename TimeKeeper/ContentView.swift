import SwiftUI
import AVKit
import UniformTypeIdentifiers

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
                        playerViewModel: playerViewModel
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
}