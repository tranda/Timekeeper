import SwiftUI

@main
struct TimeKeeperApp: App {
    @State private var showingHelp = false
    @State private var showingAbout = false
    @State private var showingLog = false
    @State private var showingAPIKeySetup = false
    @State private var showingSettings = false
    @State private var apiKeyInput = ""
    @State private var showingRacePlanResult = false
    @State private var racePlanResultMessage = ""
    @State private var racePlanResultIsSuccess = false
    @StateObject private var racePlanService = RacePlanService.shared
    @StateObject private var captureManager = CaptureManager()

    var body: some Scene {
        WindowGroup {
            ContentView(captureManager: captureManager)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    // Maximize window on startup
                    if let window = NSApplication.shared.windows.first {
                        window.setFrame(NSScreen.main?.visibleFrame ?? window.frame, display: true)
                    }
                }
                .alert("TimeKeeper Help", isPresented: $showingHelp) {
                    Button("OK") { }
                } message: {
                    Text(helpMessage)
                }
                .sheet(isPresented: $showingAPIKeySetup) {
                    VStack(spacing: 20) {
                        Text("API Key Configuration")
                            .font(.title2)
                            .bold()

                        Text("Enter your API key to access race plan data:")
                            .font(.body)
                            .multilineTextAlignment(.center)

                        SecureField("Enter API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)

                        HStack(spacing: 20) {
                            Button("Cancel") {
                                showingAPIKeySetup = false
                                apiKeyInput = ""
                            }
                            .keyboardShortcut(.escape)

                            Button("Save") {
                                if KeychainService.shared.saveAPIKey(apiKeyInput) {
                                    showingAPIKeySetup = false
                                    apiKeyInput = ""
                                }
                            }
                            .keyboardShortcut(.return)
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKeyInput.isEmpty)
                        }
                    }
                    .padding(40)
                    .frame(width: 450)
                }
                .alert(racePlanResultIsSuccess ? "Success" : "Error", isPresented: $showingRacePlanResult) {
                    Button("OK") { }
                } message: {
                    Text(racePlanResultMessage)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(captureManager: captureManager)
                }
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
                .sheet(isPresented: $showingLog) {
                    LogView()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appInfo) {
                Button("About TimeKeeper") {
                    showingAbout = true
                }

                Divider()

                Button("Show Log…") {
                    showingLog = true
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .help) {
                Button("TimeKeeper Help") {
                    showingHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button("Set API Key...") {
                    showingAPIKeySetup = true
                }

                Divider()

                Button("Load Race Plans") {
                    racePlanService.fetchRacePlans()
                    // Monitor the result and show feedback
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        observeRacePlanResult()
                    }
                }
                .disabled(!racePlanService.hasAPIKey() || racePlanService.isLoading)

                Button("Clear Race Plans") {
                    racePlanService.clearRacePlans()
                    racePlanResultMessage = "Race plans cleared successfully"
                    racePlanResultIsSuccess = true
                    showingRacePlanResult = true
                }
                .disabled(racePlanService.availableRacePlan == nil)
            }
        }
    }

    private func observeRacePlanResult() {
        // Check loading state and wait for completion
        if racePlanService.isLoading {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                observeRacePlanResult()
            }
            return
        }

        // Check result
        if let errorMessage = racePlanService.errorMessage {
            racePlanResultMessage = errorMessage
            racePlanResultIsSuccess = false
            showingRacePlanResult = true
        } else if let racePlan = racePlanService.availableRacePlan {
            let raceCount = racePlan.races.count
            racePlanResultMessage = "Successfully loaded \"\(racePlan.eventName)\" with \(raceCount) race(s)"
            racePlanResultIsSuccess = true
            showingRacePlanResult = true
        } else {
            racePlanResultMessage = "No race plans found"
            racePlanResultIsSuccess = false
            showingRacePlanResult = true
        }
    }

    private var helpMessage: String {
        """
        KEYBOARD SHORTCUTS

        Race Setup:
        • ENTER - Start Race

        During Race:
        • SPACE - Record Video
        • ESC - Stop Race & Recording

        After Race (Video Review):
        • M - Open lane selection dialog
        • F - Toggle photo finish overlay
        • ←/→ - Navigate timeline ±10ms
        • ⇧+←/→ - Navigate ±1ms (fine)
        • ⌘+←/→ - Navigate ±100ms (coarse)
        • ⌘+E - Export current frame
        • ⌘+S - Save session
        • ⌘++ - Zoom in video
        • ⌘+- - Zoom out video
        • ⌘+0 - Reset zoom

        WORKFLOW:
        1. Click NEW RACE and set up lanes
        2. Press ENTER to start race
        3. Press SPACE to record finish area
        4. Press ESC to stop race & recording
        5. Use M to add finish markers
        6. Use F for photo finish analysis
        7. Navigate video with arrow keys
        8. Export frames or save session
        """
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "TimeKeeper"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildDate: String {
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let date = attrs[.modificationDate] as? Date else {
            return "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text(appName)
                .font(.title)
                .bold()

            VStack(spacing: 6) {
                HStack {
                    Text("Version:").bold()
                    Text(version)
                }
                HStack {
                    Text("Author:").bold()
                    Text("Zoran Trandafilovic")
                }
                HStack {
                    Text("Last Build:").bold()
                    Text(buildDate)
                }
            }
            .font(.callout)

            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
        .padding(30)
        .frame(width: 360)
    }
}