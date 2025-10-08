import SwiftUI
import AVFoundation

struct SettingsView: View {
    @State private var maxLanes: Int = AppConfig.shared.maxLanes
    @State private var outputDirectory: URL?
    @State private var selectedDeviceID: String?
    @State private var availableDevices: [AVCaptureDevice] = []
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

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output Folder:")
                            Text(outputDirectory?.path ?? (FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "Temporary Directory"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Choose...") {
                            selectOutputFolder()
                        }
                    }

                    Text("Location where race data and exported images are saved")
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
                        }
                    }

                    Text("Camera used for recording races")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .frame(width: 500, height: 500)
        .onAppear {
            // Load output directory from UserDefaults (same key as CaptureManager)
            if let path = UserDefaults.standard.string(forKey: "outputDirectory") {
                outputDirectory = URL(fileURLWithPath: path)
            }

            // Load available camera devices
            refreshCameraDevices()

            // Load selected camera device from UserDefaults
            selectedDeviceID = UserDefaults.standard.string(forKey: "selectedCameraDevice")
        }
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"

        if panel.runModal() == .OK {
            outputDirectory = panel.url
            // Save to UserDefaults so it persists and can be read by other parts of the app
            UserDefaults.standard.set(panel.url?.path, forKey: "outputDirectory")
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