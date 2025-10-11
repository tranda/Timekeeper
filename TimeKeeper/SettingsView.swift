import SwiftUI
import AVFoundation

struct SettingsView: View {
    @State private var maxLanes: Int = AppConfig.shared.maxLanes
    @State private var freeRacesDirectory: URL?
    @State private var eventRacesDirectory: URL?
    @State private var selectedDeviceID: String?
    @State private var availableDevices: [AVCaptureDevice] = []
    @State private var selectedQuality: VideoQuality = VideoQuality.standardPresets[1] // Default to HD 1080p
    @State private var availableQualities: [VideoQuality] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Race Configuration")
                        .font(.headline)

                    HStack {
                        Text("Maximum Number of Lanes:")
                        Spacer()
                        TextField("Lanes", value: $maxLanes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onChange(of: maxLanes) { newValue in
                                // Validate range
                                if newValue < 1 {
                                    maxLanes = 1
                                } else if newValue > 12 {
                                    maxLanes = 12
                                }
                            }
                    }

                    Text("Valid range: 1-12 lanes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("File Storage")
                        .font(.headline)

                    // Free Races Output Folder
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Free Races Folder:")
                            Text(freeRacesDirectory?.path ?? (FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.appendingPathComponent("FreeRaces").path ?? "Temporary Directory"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Choose...") {
                            selectFreeRacesFolder()
                        }
                    }

                    // Event Races Output Folder
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Event Races Folder:")
                            Text(eventRacesDirectory?.path ?? (FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.appendingPathComponent("EventRaces").path ?? "Temporary Directory"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Choose...") {
                            selectEventRacesFolder()
                        }
                    }

                    Text("Separate locations for Free Races and Event-based races")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Camera Input")
                        .font(.headline)

                    HStack {
                        Text("Camera Device:")

                        Spacer()

                        Picker("", selection: $selectedDeviceID) {
                            Text("None").tag(nil as String?)
                            ForEach(availableDevices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID as String?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: selectedDeviceID) { newDeviceID in
                            // Save selected device to UserDefaults
                            UserDefaults.standard.set(newDeviceID, forKey: "selectedCameraDevice")

                            // Notify CaptureManager to switch to the new camera
                            if let deviceID = newDeviceID,
                               let device = availableDevices.first(where: { $0.uniqueID == deviceID }) {
                                // Post notification for CaptureManager to switch cameras
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("CameraSwitchRequested"),
                                    object: device
                                )
                            }
                        }
                    }

                    Text("Camera used for recording races")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Quality")
                        .font(.headline)

                    HStack {
                        Text("Recording Quality:")

                        Spacer()

                        Picker("", selection: $selectedQuality) {
                            ForEach(availableQualities, id: \.self) { quality in
                                Text(quality.uniqueID).tag(quality)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: selectedQuality) { newQuality in
                            // Save selected quality to UserDefaults using unique identifier
                            UserDefaults.standard.set(newQuality.uniqueID, forKey: "selectedVideoQuality")

                            // Notify CaptureManager of quality change
                            NotificationCenter.default.post(
                                name: NSNotification.Name("VideoQualityChanged"),
                                object: newQuality
                            )
                        }
                    }

                    if availableQualities.isEmpty {
                        Text("No camera selected - quality options will appear after selecting a camera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Available qualities depend on the selected camera device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                Text("Note: Changing the number of lanes will take effect when you create a new race.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    AppConfig.shared.maxLanes = maxLanes
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 640)
        .onAppear {
            // Load Free Races directory from UserDefaults
            if let path = UserDefaults.standard.string(forKey: "freeRacesDirectory") {
                freeRacesDirectory = URL(fileURLWithPath: path)
            } else {
                // Default to Desktop/FreeRaces
                freeRacesDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.appendingPathComponent("FreeRaces")
            }

            // Load Event Races directory from UserDefaults
            if let path = UserDefaults.standard.string(forKey: "eventRacesDirectory") {
                eventRacesDirectory = URL(fileURLWithPath: path)
            } else {
                // Default to Desktop/EventRaces
                eventRacesDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.appendingPathComponent("EventRaces")
            }

            // Load available camera devices
            refreshCameraDevices()

            // Load selected camera device from UserDefaults
            selectedDeviceID = UserDefaults.standard.string(forKey: "selectedCameraDevice")

            // Load saved video quality
            if let savedQualityID = UserDefaults.standard.string(forKey: "selectedVideoQuality"),
               let quality = VideoQuality.standardPresets.first(where: { $0.uniqueID == savedQualityID }) {
                selectedQuality = quality
            }

            // Listen for quality updates from CaptureManager
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("AvailableQualitiesUpdated"),
                object: nil,
                queue: .main
            ) { notification in
                if let qualities = notification.object as? [VideoQuality] {
                    availableQualities = qualities
                    // Update selected quality if it's not available
                    if !qualities.contains(selectedQuality), let firstQuality = qualities.first {
                        selectedQuality = firstQuality
                    }
                }
            }
        }
    }

    private func selectFreeRacesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Free Races Folder"

        if panel.runModal() == .OK {
            freeRacesDirectory = panel.url
            // Save to UserDefaults so it persists and can be read by other parts of the app
            UserDefaults.standard.set(panel.url?.path, forKey: "freeRacesDirectory")
            print("💾 Saved Free Races directory: \(panel.url?.path ?? "nil")")
        }
    }

    private func selectEventRacesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Event Races Folder"

        if panel.runModal() == .OK {
            eventRacesDirectory = panel.url
            // Save to UserDefaults so it persists and can be read by other parts of the app
            UserDefaults.standard.set(panel.url?.path, forKey: "eventRacesDirectory")
            print("💾 Saved Event Races directory: \(panel.url?.path ?? "nil")")
        }
    }

    private func refreshCameraDevices() {
        // Get available video capture devices
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        availableDevices = discoverySession.devices
    }
}

#Preview {
    SettingsView()
}