import SwiftUI
import AppKit

struct LogView: View {
    @ObservedObject private var log: AppLog = .shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Session Log").font(.headline)
                Spacer()
                Text("\(log.lines.count) line\(log.lines.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                                .id(idx)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onAppear {
                    if let last = log.lines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
                .onChange(of: log.lines.count) { _ in
                    if let last = log.lines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("Copy All") {
                    let text = log.lines.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(log.lines.isEmpty)

                Button("Clear") {
                    log.clear()
                }
                .disabled(log.lines.isEmpty)

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([log.logFileURL])
                }

                Spacer()

                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

#Preview {
    LogView()
}
