import Foundation
import Combine

/// In-memory + on-disk log buffer. Singleton — `AppLog.shared`.
/// On-disk logs are cumulative and dated, one file per day:
///   ~/Library/Logs/TimeKeeper/TimeKeeper-2026-09-27.log
/// Every launch appends to today's file; the file rolls over at midnight.
/// Log files are never deleted or truncated by the app.
final class AppLog: ObservableObject {
    static let shared = AppLog()

    /// Recent log lines of this launch (oldest first). Capped at `maxLines`.
    @Published private(set) var lines: [String] = []
    /// File currently being written.
    @Published private(set) var logFileURL: URL

    let logDirectory: URL
    private let maxLines = 5000
    private let filePrefix = "TimeKeeper-"
    private var fileHandle: FileHandle?
    private var currentDay: String
    private let queue = DispatchQueue(label: "com.timekeeper.applog")

    private init() {
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        logDirectory = libraryDir.appendingPathComponent("Logs/TimeKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let now = Date()
        currentDay = AppLog.dayFormatter.string(from: now)
        logFileURL = logDirectory.appendingPathComponent("\(filePrefix)\(currentDay).log")
        openCurrentFile()
        appendToFile("")
        appendToFile("===== [\(AppLog.dateTimeFormatter.string(from: now))] TimeKeeper \(AppLog.appVersion) launched =====")
    }

    /// Append a log line. Thread-safe.
    func write(_ message: String) {
        let now = Date()
        let stamped = "[\(AppLog.timestampFormatter.string(from: now))] \(message)"
        queue.async { [weak self] in
            guard let self = self else { return }
            self.rollOverIfNewDay(now)
            self.appendToFile(stamped)
            DispatchQueue.main.async {
                self.lines.append(stamped)
                if self.lines.count > self.maxLines {
                    self.lines.removeFirst(self.lines.count - self.maxLines)
                }
            }
        }
    }

    /// Clears the on-screen buffer only; the log file on disk is not touched.
    func clearView() {
        DispatchQueue.main.async {
            self.lines.removeAll()
        }
    }

    // MARK: - File handling (called on `queue`, or from init)

    private func appendToFile(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try? fileHandle?.seekToEnd()
        fileHandle?.write(data)
    }

    private func openCurrentFile() {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
    }

    private func switchFile(to url: URL) {
        try? fileHandle?.close()
        DispatchQueue.main.async { self.logFileURL = url }
        // Open synchronously so the next append on this queue goes to the new file
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
    }

    private func rollOverIfNewDay(_ now: Date) {
        let day = AppLog.dayFormatter.string(from: now)
        guard day != currentDay else { return }
        currentDay = day
        switchFile(to: logDirectory.appendingPathComponent("\(filePrefix)\(day).log"))
        appendToFile("===== [\(AppLog.dateTimeFormatter.string(from: now))] New day (TimeKeeper \(AppLog.appVersion)) =====")
    }

    // MARK: - Formatting

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private static let timestampFormatter = formatter("HH:mm:ss.SSS")
    private static let dayFormatter = formatter("yyyy-MM-dd")
    private static let dateTimeFormatter = formatter("yyyy-MM-dd HH:mm:ss")

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static func timestamp() -> String {
        return timestampFormatter.string(from: Date())
    }
}

// Shadow Swift.print within this module so every existing print() call
// also feeds AppLog. Xcode's debug console still receives output via Swift.print.
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let message = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(message, terminator: terminator)
    AppLog.shared.write(message)
}
