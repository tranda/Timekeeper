import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        Text("TimeKeeper Help")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)

                        Text("Professional Race Timing with Video Review")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)

                    // Keyboard Shortcuts Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Keyboard Shortcuts")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)

                        // Race Control
                        ShortcutSection(
                            title: "Race Control",
                            shortcuts: [
                                ("SPACE", "Record Video", "Most accessible key for critical recording"),
                                ("ENTER", "Start/Stop Race", "Toggle race timing on/off"),
                                ("ESC", "Emergency Stop", "Stop both race timing and video recording")
                            ]
                        )

                        // Timeline Navigation
                        ShortcutSection(
                            title: "Timeline Navigation (Video Review)",
                            shortcuts: [
                                ("← / →", "Navigate timeline", "±10ms (standard)"),
                                ("⇧ + ← / →", "Fine navigation", "±1ms (precise)"),
                                ("⌘ + ← / →", "Coarse navigation", "±100ms (quick)"),
                                ("Home / End", "Jump to start/end", "Video boundaries")
                            ]
                        )

                        // Finish Marking
                        ShortcutSection(
                            title: "Finish Marking",
                            shortcuts: [
                                ("M", "Add Marker", "Lane must be selected first (1-9)"),
                                ("Delete / ⌫", "Remove last marker", "Removes most recent finish marker")
                            ]
                        )

                        // Lane Management
                        ShortcutSection(
                            title: "Lane Management",
                            shortcuts: [
                                ("1-9", "Select Lane", "Choose active lane for marker placement"),
                                ("D", "Mark DNS", "Did Not Start (selected lane)"),
                                ("N", "Mark DNF", "Did Not Finish (selected lane)"),
                                ("S", "Mark DSQ", "Disqualified (selected lane)")
                            ]
                        )

                        // Quick Actions
                        ShortcutSection(
                            title: "Quick Actions",
                            shortcuts: [
                                ("⌘ + E", "Export Frame", "Export current video frame as JPEG"),
                                ("⌘ + S", "Save Session", "Save current race timing data")
                            ]
                        )
                    }

                    Divider()

                    // Workflow Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Typical Race Timing Workflow")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)

                        WorkflowSection(
                            title: "Setup Phase",
                            steps: [
                                "Click \"NEW RACE\" and enter race name and team/lane names",
                                "Select camera from the dropdown menu",
                                "Choose output folder for recordings and data"
                            ]
                        )

                        WorkflowSection(
                            title: "Race Timing",
                            steps: [
                                "Press ENTER to start race timing",
                                "Press SPACE to begin video recording when competitors approach finish line",
                                "Press ENTER to stop race timing when all competitors have finished",
                                "Recording automatically stops when race ends"
                            ]
                        )

                        WorkflowSection(
                            title: "Video Review & Precise Timing",
                            steps: [
                                "Use 1-9 to select a lane",
                                "Navigate video with ← / → arrows",
                                "Use ⇧ + arrows for frame-by-frame precision",
                                "Press M to set finish marker at current position",
                                "Repeat for each lane",
                                "Press ⌘ + E to export finish line photo if needed"
                            ]
                        )
                    }

                    Divider()

                    // Tips and Notes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Important Notes")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 8) {
                            HelpNote(
                                icon: "info.circle.fill",
                                color: .blue,
                                text: "You must select a lane (1-9) before adding a marker with the M key. The selected lane is shown in the \"Selected Lane\" indicator on the left panel."
                            )

                            HelpNote(
                                icon: "lightbulb.fill",
                                color: .orange,
                                text: "For the most accurate timing, record only the finish line area. Start recording just before the first competitor arrives and stop after the last competitor finishes."
                            )

                            HelpNote(
                                icon: "checkmark.circle.fill",
                                color: .green,
                                text: "All race data is automatically saved as JSON files alongside video recordings. Video and timing data are perfectly synchronized for precise analysis."
                            )
                        }
                    }

                    Divider()

                    // Lane Status
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Lane Status Management")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)

                        Text("TimeKeeper supports standard race statuses:")
                            .font(.body)

                        VStack(alignment: .leading, spacing: 5) {
                            StatusRow(status: "Registered", description: "Default status before race")
                            StatusRow(status: "Finished", description: "Competitor completed the race (set by adding markers)")
                            StatusRow(status: "DNS", description: "Did Not Start")
                            StatusRow(status: "DNF", description: "Did Not Finish")
                            StatusRow(status: "DSQ", description: "Disqualified")
                        }
                    }

                    // System Requirements
                    VStack(alignment: .leading, spacing: 10) {
                        Text("System Requirements")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)

                        HelpNote(
                            icon: "desktopcomputer",
                            color: .secondary,
                            text: "TimeKeeper requires macOS 13.0 (Ventura) or later and camera access permissions for video recording."
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .frame(width: 800, height: 700)
    }
}

struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    HStack {
                        Text(shortcut.0)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                            .frame(minWidth: 80, alignment: .center)

                        Text(shortcut.1)
                            .font(.system(.caption, weight: .medium))
                            .frame(minWidth: 100, alignment: .leading)

                        Text(shortcut.2)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.leading, 10)
        }
    }
}

struct WorkflowSection: View {
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .frame(width: 20, alignment: .trailing)

                        Text(step)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 10)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct HelpNote: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct StatusRow: View {
    let status: String
    let description: String

    var body: some View {
        HStack {
            Text("•")
                .foregroundColor(.blue)
            Text("\(status):")
                .fontWeight(.medium)
            Text(description)
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

#Preview {
    HelpView()
}