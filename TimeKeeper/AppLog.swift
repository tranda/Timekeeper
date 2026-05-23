import Foundation
import Combine

/// In-memory + on-disk log buffer. Singleton — `AppLog.shared`.
/// The on-disk file is truncated each launch and lives at:
///   ~/Library/Caches/TimeKeeper/session.log
final class AppLog: ObservableObject {
    static let shared = AppLog()

    /// Recent log lines (oldest first). Capped at `maxLines`.
    @Published private(set) var lines: [String] = []

    private let maxLines = 5000
    let logFileURL: URL
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.timekeeper.applog")

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let appCacheDir = cacheDir.appendingPathComponent("TimeKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        logFileURL = appCacheDir.appendingPathComponent("session.log")
        // Truncate on each launch
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
    }

    /// Append a log line. Thread-safe.
    func write(_ message: String) {
        let stamped = "[\(AppLog.timestamp())] \(message)"
        queue.async { [weak self] in
            guard let self = self else { return }
            if let data = (stamped + "\n").data(using: .utf8) {
                try? self.fileHandle?.seekToEnd()
                self.fileHandle?.write(data)
            }
            DispatchQueue.main.async {
                self.lines.append(stamped)
                if self.lines.count > self.maxLines {
                    self.lines.removeFirst(self.lines.count - self.maxLines)
                }
            }
        }
    }

    func clear() {
        queue.async { [weak self] in
            try? self?.fileHandle?.truncate(atOffset: 0)
            DispatchQueue.main.async {
                self?.lines.removeAll()
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

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
