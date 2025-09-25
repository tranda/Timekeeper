import SwiftUI

@main
struct TimeKeeperApp: App {
    @State private var showingHelp = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 920, minHeight: 620)
                .alert("TimeKeeper Help", isPresented: $showingHelp) {
                    Button("OK") { }
                } message: {
                    Text(helpMessage)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) {
                Button("TimeKeeper Help") {
                    showingHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
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
        • ←/→ - Navigate timeline ±10ms
        • ⇧+←/→ - Navigate ±1ms (fine)
        • ⌘+←/→ - Navigate ±100ms (coarse)
        • ⌘+E - Export current frame
        • ⌘+S - Save session

        WORKFLOW:
        1. Click NEW RACE and set up lanes
        2. Press ENTER to start race
        3. Press SPACE to record finish area
        4. Press ESC to stop race & recording
        5. Use M to add finish markers
        6. Navigate video with arrow keys
        7. Export frames or save session
        """
    }
}