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
                            Text(outputFolderURL?.lastPathComponent ?? "Not Set")
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
            GeometryReader { geometry in
                VStack(spacing: 10) {
                // Always show camera preview at the top if available
                if captureManager.captureSession != nil {
                    VStack(spacing: 5) {
                        Text("Live Camera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VideoPreviewView(session: captureManager.captureSession!)
                            .frame(height: min(250, geometry.size.height * 0.3))
                            .background(Color.black)
                            .cornerRadius(8)
                    }
                }

                // Show recorded video player when we have a recording to review
                if !timingModel.isRaceActive && captureManager.lastRecordedURL != nil {
                    VStack(spacing: 5) {
                        Text("Recorded Video")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        GeometryReader { geometry in
                            let availableWidth = geometry.size.width
                            // Assuming 9:16 aspect ratio for vertical phone video
                            let videoAspectRatio: CGFloat = 9.0 / 16.0
                            let videoWidth = min(availableWidth * 0.4, 250)
                            let videoHeight = videoWidth / videoAspectRatio

                            HStack {
                                Spacer()
                                VideoPlayer(player: playerViewModel.player)
                                    .frame(width: videoWidth, height: videoHeight)
                                    .background(Color.black)
                                    .cornerRadius(8)
                                    .onAppear {
                                        if let url = captureManager.lastRecordedURL {
                                            playerViewModel.loadVideo(url: url)
                                        }
                                    }
                                Spacer()
                            }
                        }
                        .frame(height: 250)
                    }
                }

                // Show race timeline after race is stopped
                if !timingModel.isRaceActive && timingModel.raceStartTime != nil {
                    RaceTimelineView(
                        timingModel: timingModel,
                        captureManager: captureManager,
                        playerViewModel: playerViewModel
                    )
                    .padding(.horizontal)
                } else if !timingModel.isRaceActive && (recordedVideoURL != nil || captureManager.lastRecordedURL != nil),
                          let videoURL = recordedVideoURL ?? captureManager.lastRecordedURL {
                    // Legacy video player for when no race timing exists
                    VStack {
                    GeometryReader { geometry in
                        let availableWidth = geometry.size.width
                        // Assuming 9:16 aspect ratio for vertical phone video
                        let videoAspectRatio: CGFloat = 9.0 / 16.0
                        let videoWidth = min(availableWidth * 0.6, 400)
                        let videoHeight = videoWidth / videoAspectRatio

                        HStack {
                            Spacer()
                            VideoPlayer(player: playerViewModel.player)
                                .frame(width: videoWidth, height: videoHeight)
                                .background(Color.black)
                            Spacer()
                        }
                    }
                    .frame(height: 500)
                        .onAppear {
                            if let url = videoURL ?? captureManager.lastRecordedURL {
                                playerViewModel.loadVideo(url: url)
                            }
                        }

                    VStack(spacing: 10) {
                        HStack {
                            Toggle("Sync to START", isOn: $syncToRaceTime)
                                .toggleStyle(.checkbox)
                                .disabled(timingModel.raceStartTime == nil)

                            Spacer()

                            if syncToRaceTime && !timingModel.finishEvents.isEmpty {
                                HStack {
                                    Text("Jump to:")
                                        .foregroundColor(.secondary)
                                    ForEach(timingModel.finishEvents.prefix(5)) { event in
                                        Button(formatTime(event.tRace)) {
                                            let videoTime = timingModel.videoTimeForRaceTime(event.tRace)
                                            playerViewModel.seek(to: videoTime, precise: true)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if timingModel.finishEvents.count > 5 {
                                        Menu("More...") {
                                            ForEach(timingModel.finishEvents.dropFirst(5)) { event in
                                                Button(formatTime(event.tRace)) {
                                                    let videoTime = timingModel.videoTimeForRaceTime(event.tRace)
                                                    playerViewModel.seek(to: videoTime, precise: true)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        Slider(value: Binding(
                            get: {
                                if syncToRaceTime, let raceTime = timingModel.raceTimeForVideoTime(playerViewModel.currentTime) {
                                    return raceTime
                                }
                                return playerViewModel.currentTime
                            },
                            set: { newValue in
                                if syncToRaceTime {
                                    let videoTime = timingModel.videoTimeForRaceTime(newValue)
                                    playerViewModel.seek(to: videoTime)
                                } else {
                                    playerViewModel.seek(to: newValue)
                                }
                            }
                        ), in: 0...(syncToRaceTime && timingModel.sessionData != nil ? max(0, playerViewModel.duration - (timingModel.sessionData?.raceStartInVideoSeconds ?? 0)) : playerViewModel.duration))
                        .disabled(playerViewModel.duration == 0)

                        HStack {
                            Text(formatTime(syncToRaceTime && timingModel.raceTimeForVideoTime(playerViewModel.currentTime) != nil ?
                                          timingModel.raceTimeForVideoTime(playerViewModel.currentTime)! : playerViewModel.currentTime))
                                .monospacedDigit()
                            Spacer()
                            Text(formatTime(syncToRaceTime && timingModel.sessionData != nil ? max(0, playerViewModel.duration - (timingModel.sessionData?.raceStartInVideoSeconds ?? 0)) : playerViewModel.duration))
                                .monospacedDigit()
                        }
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .padding(.horizontal)

                    HStack {
                        Button(action: { playerViewModel.seekToPreviousFrame() }) {
                            Image(systemName: "backward.frame")
                        }
                        .keyboardShortcut(.leftArrow, modifiers: [])

                        Button(action: { playerViewModel.togglePlayPause() }) {
                            Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .keyboardShortcut(.space, modifiers: [])

                        Button(action: { playerViewModel.seekToNextFrame() }) {
                            Image(systemName: "forward.frame")
                        }
                        .keyboardShortcut(.rightArrow, modifiers: [])

                        Divider()
                            .frame(height: 20)

                        Button(action: exportCurrentFrame) {
                            Label("Export Frame", systemImage: "photo")
                        }
                        .disabled(isExporting)
                        .buttonStyle(.borderedProminent)

                        Button("Load Last Clip") {
                            loadLastClip()
                        }

                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                    }
                } else {
                    // No camera selected or preview available
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .alert("Export Complete", isPresented: $showExportSuccess) {
            Button("OK") { }
        } message: {
            Text("Frame exported successfully")
        }
        .onAppear {
            captureManager.checkPermissions()
            captureManager.refreshDevices()
            captureManager.timingModel = timingModel
            playerViewModel.timingModel = timingModel

            // Delay device selection to ensure devices are loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let firstDevice = captureManager.availableDevices.first {
                    selectedDeviceID = firstDevice.uniqueID
                    captureManager.selectDevice(firstDevice)
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

            let sessionURL = lastURL.deletingLastPathComponent().appendingPathComponent("session.json")
            if FileManager.default.fileExists(atPath: sessionURL.path) {
                timingModel.loadSession(from: sessionURL)
                syncToRaceTime = timingModel.raceStartTime != nil
            }
        }
    }
}