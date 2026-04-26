import SwiftUI
import AVFoundation
import AppKit

/// Sheet shown while the motion sweep runs across the entire clip.
/// Writes a CSV of per-frame energy + a crossings CSV of detected peaks next to the .mov.
/// Detected crossings are shown in a list with seek buttons.
struct MotionSweepSheet: View {
    let videoURL: URL
    let p1: CGPoint
    let p2: CGPoint
    let roiHalfWidthPx: Int
    let tStart: Double
    let tEnd: Double
    let initialThreshold: Int
    let initialRows: [SweepRow]
    let initialCrossings: [CrossingEvent]
    let onSeek: (Double) -> Void
    let onSweepCompleted: ([SweepRow], [CrossingEvent]) -> Void
    let onClose: () -> Void

    @State private var threshold: Int
    @State private var frameStride: Int = 1
    @State private var peakMultiplier: Double = 2.5
    @State private var minSeparationSec: Double = 2.0
    @State private var progress: Double = 0
    @State private var status: String = "Ready"
    @State private var isRunning = false
    @State private var sweepTask: Task<Void, Never>? = nil
    @State private var rowsCsvURL: URL? = nil
    @State private var crossingsCsvURL: URL? = nil
    @State private var crossings: [CrossingEvent] = []
    @State private var errorMessage: String? = nil
    /// Thumbnail cache, keyed by crossing time.
    @State private var thumbs: [Double: NSImage] = [:]

    init(videoURL: URL,
         p1: CGPoint, p2: CGPoint, roiHalfWidthPx: Int,
         tStart: Double, tEnd: Double,
         initialThreshold: Int,
         initialRows: [SweepRow] = [],
         initialCrossings: [CrossingEvent] = [],
         onSeek: @escaping (Double) -> Void,
         onSweepCompleted: @escaping ([SweepRow], [CrossingEvent]) -> Void,
         onClose: @escaping () -> Void) {
        self.videoURL = videoURL
        self.p1 = p1
        self.p2 = p2
        self.roiHalfWidthPx = roiHalfWidthPx
        self.tStart = tStart
        self.tEnd = tEnd
        self.initialThreshold = initialThreshold
        self.initialRows = initialRows
        self.initialCrossings = initialCrossings
        self.onSeek = onSeek
        self.onSweepCompleted = onSweepCompleted
        self.onClose = onClose
        self._threshold = State(initialValue: initialThreshold)
        self._lastRows = State(initialValue: initialRows)
        self._crossings = State(initialValue: initialCrossings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Motion Sweep — Crossing Detection")
                .font(.title2).bold()
            Text("Source: \(videoURL.lastPathComponent)")
                .font(.caption).foregroundColor(.secondary)
            Text("ROI: ±\(roiHalfWidthPx) px from finish line")
                .font(.caption).foregroundColor(.secondary)

            Divider()

            HStack {
                Text("Threshold:")
                Stepper(value: $threshold, in: 3...200, step: 1) {
                    Text("\(threshold)").frame(width: 40, alignment: .trailing).monospacedDigit()
                }
                .disabled(isRunning)
                Spacer()
                Text("Frame stride:")
                Stepper(value: $frameStride, in: 1...10) {
                    Text("\(frameStride)").frame(width: 40, alignment: .trailing).monospacedDigit()
                }
                .disabled(isRunning)
            }
            HStack {
                Text("Peak multiplier (× median):")
                Stepper(value: $peakMultiplier, in: 1.5...10.0, step: 0.5) {
                    Text(String(format: "%.1f×", peakMultiplier))
                        .frame(width: 50, alignment: .trailing).monospacedDigit()
                }
                .disabled(isRunning)
                Spacer()
                Text("Min separation:")
                Stepper(value: $minSeparationSec, in: 0.1...5.0, step: 0.1) {
                    Text(String(format: "%.1fs", minSeparationSec))
                        .frame(width: 50, alignment: .trailing).monospacedDigit()
                }
                .disabled(isRunning)
            }

            ProgressView(value: progress).progressViewStyle(.linear)
            Text(status)
                .font(.caption)
                .foregroundColor(errorMessage == nil ? .secondary : .red)

            // Crossings list
            if !crossings.isEmpty {
                Divider()
                Text("Detected crossings (\(crossings.count))").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(crossings.enumerated()), id: \.offset) { idx, c in
                            HStack(spacing: 10) {
                                Text("#\(idx + 1)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 26, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                // Thumbnail
                                ZStack {
                                    Rectangle().fill(Color.black.opacity(0.4))
                                        .frame(width: 96, height: 54)
                                    if let img = thumbs[c.time] {
                                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                            .frame(width: 96, height: 54).clipped()
                                    } else {
                                        ProgressView().controlSize(.mini)
                                    }
                                }
                                .cornerRadius(3)
                                .onTapGesture { onSeek(c.time) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatTime(c.time))
                                        .font(.body.monospacedDigit())
                                    Text("energy=\(c.peakEnergy)  pos=\(String(format: "%.2f", c.centroidOffsetAlongLine))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Go to") { onSeek(c.time) }
                                    .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .border(Color.secondary.opacity(0.3))
                .task(id: crossings.map { $0.time }) {
                    await loadThumbnails()
                }
            }

            HStack {
                if !isRunning {
                    Button(rowsCsvURL == nil ? "Run Sweep" : "Run New Sweep") { startSweep() }
                        .keyboardShortcut(.defaultAction)
                }
                if isRunning {
                    Button("Cancel") {
                        sweepTask?.cancel()
                        status = "Cancelled."
                        isRunning = false
                    }
                }
                if !lastRows.isEmpty {
                    Button("Re-detect Peaks") {
                        Task { await rerunPeakDetection() }
                    }
                }
                if let rows = rowsCsvURL {
                    Button("Reveal CSVs in Finder") {
                        let urls: [URL] = [rows, crossingsCsvURL].compactMap { $0 }
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                    }
                }
                Spacer()
                Button("Close") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isRunning)
            }
        }
        .padding(20)
        .frame(width: 720, height: 660)
        .onAppear {
            // Restore "completed" state if we were given prior results.
            if !initialRows.isEmpty && rowsCsvURL == nil {
                let rURL = csvURL(for: videoURL, suffix: "_motion_sweep")
                let xURL = csvURL(for: videoURL, suffix: "_crossings")
                if FileManager.default.fileExists(atPath: rURL.path) { rowsCsvURL = rURL }
                if FileManager.default.fileExists(atPath: xURL.path) { crossingsCsvURL = xURL }
                progress = 1.0
                status = "Previous sweep loaded — \(initialRows.count) frames, \(initialCrossings.count) crossings. Adjust sliders + Re-detect Peaks, or Run a new sweep."
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", m, s, ms)
    }

    @State private var lastRows: [SweepRow] = []

    private func startSweep() {
        let asset = AVAsset(url: videoURL)
        guard CMTimeGetSeconds(asset.duration) > 0 else {
            errorMessage = "Video has zero duration."
            status = errorMessage!
            return
        }
        progress = 0
        status = "Running…"
        errorMessage = nil
        isRunning = true
        crossings = []

        let p1c = p1, p2c = p2, roi = roiHalfWidthPx
        let thr = threshold, str = frameStride
        let mult = peakMultiplier, sep = minSeparationSec
        let ts = tStart, te = tEnd

        sweepTask = Task {
            do {
                let rows = try await MotionInspector.sweep(
                    asset: asset,
                    normalizedP1: p1c, normalizedP2: p2c,
                    roiHalfWidthPx: roi,
                    threshold: thr,
                    tStart: ts, tEnd: te,
                    frameStride: str,
                    progress: { p in
                        Task { @MainActor in self.progress = p }
                    }
                )
                let detected = MotionInspector.detectCrossings(
                    rows: rows, peakMultiplier: mult, minSeparationSeconds: sep
                )
                let rowsURL = csvURL(for: videoURL, suffix: "_motion_sweep")
                let xURL = csvURL(for: videoURL, suffix: "_crossings")
                try writeRowsCSV(rows: rows, to: rowsURL)
                try writeCrossingsCSV(events: detected, to: xURL)
                await MainActor.run {
                    self.lastRows = rows
                    self.rowsCsvURL = rowsURL
                    self.crossingsCsvURL = xURL
                    self.crossings = detected
                    self.isRunning = false
                    self.status = "Done — \(rows.count) frames analyzed, \(detected.count) crossings detected."
                    self.onSweepCompleted(rows, detected)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isRunning = false
                    self.status = "Cancelled."
                }
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.errorMessage = error.localizedDescription
                    self.status = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func rerunPeakDetection() async {
        guard !lastRows.isEmpty else { return }
        let detected = MotionInspector.detectCrossings(
            rows: lastRows, peakMultiplier: peakMultiplier, minSeparationSeconds: minSeparationSec
        )
        if let xURL = crossingsCsvURL {
            try? writeCrossingsCSV(events: detected, to: xURL)
        }
        await MainActor.run {
            self.crossings = detected
            self.status = "Re-detected: \(detected.count) crossings (mult=\(String(format: "%.1f", peakMultiplier)), sep=\(String(format: "%.1f", minSeparationSec))s)"
            self.onSweepCompleted(self.lastRows, detected)
        }
    }

    /// Generate small thumbnails for each detected crossing in the background.
    private func loadThumbnails() async {
        let asset = AVAsset(url: videoURL)
        let times = crossings.map { $0.time }
        let needed = times.filter { thumbs[$0] == nil }
        guard !needed.isEmpty else { return }
        let images = await Task.detached(priority: .userInitiated) { () -> [(Double, NSImage?)] in
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            gen.maximumSize = CGSize(width: 192, height: 108)
            return needed.map { t in
                let cmt = CMTime(seconds: t, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: cmt, actualTime: nil) {
                    return (t, NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                }
                return (t, nil)
            }
        }.value
        await MainActor.run {
            for (t, img) in images { if let img = img { thumbs[t] = img } }
        }
    }

    private func csvURL(for video: URL, suffix: String) -> URL {
        let dir = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(base)\(suffix).csv")
    }

    private func writeRowsCSV(rows: [SweepRow], to url: URL) throws {
        var s = "time_s,motion_energy,centroid_offset_along_line\n"
        s.reserveCapacity(rows.count * 32)
        for r in rows {
            s += "\(String(format: "%.4f", r.time)),\(r.motionEnergy),\(String(format: "%.4f", r.centroidOffsetAlongLine))\n"
        }
        try s.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private func writeCrossingsCSV(events: [CrossingEvent], to url: URL) throws {
        var s = "crossing_idx,time_s,peak_energy,centroid_offset_along_line\n"
        for (i, e) in events.enumerated() {
            s += "\(i + 1),\(String(format: "%.4f", e.time)),\(e.peakEnergy),\(String(format: "%.4f", e.centroidOffsetAlongLine))\n"
        }
        try s.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
