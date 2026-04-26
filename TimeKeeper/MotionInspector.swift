import Foundation
import CoreGraphics
import AVFoundation

/// One frame's motion measurement along the detection line (no lane attribution — Phase A revised).
struct SweepRow: Codable {
    let time: Double                 // seconds into video
    let motionEnergy: Int            // count of above-threshold pixels inside the ROI band
    let centroidOffsetAlongLine: Double  // 0..1 mean position of fired pixels along the line
}

/// A peak in the energy-vs-time series — interpreted as a single boat tip crossing the line.
struct CrossingEvent: Codable {
    let time: Double                     // seconds into video at peak
    let peakEnergy: Int                  // motion energy at peak
    let centroidOffsetAlongLine: Double  // 0..1 along the line at peak (operator decides which lane)
}

struct MotionAnalysisResult {
    let overlay: CGImage?                // full-frame RGBA, transparent except for fired pixels
    let energy: Int                      // total fired pixels in ROI
    let centroidOffsetAlongLine: Double  // 0..1, 0 if no fire
}

/// Phase A motion inspection — pure functions over CGImage, no UI dependencies.
///
/// Algorithm per frame:
///   1. Build baseline = mean of N preceding frames (defaults: t-0.3s, t-0.6s, t-1.0s).
///   2. Render `currentFrame` and each baseline into 8-bit grayscale buffers
///      cropped to the AABB of the line + perpendicular ROI half-width.
///   3. For each ROI pixel: diff = |current - mean(baselines)|. If diff > threshold AND
///      perpendicular distance from line ≤ roiHalfWidthPx, the pixel "fires".
///   4. Project each fired pixel onto the line's parametric position t∈[0,1] and bucket
///      into lane = floor(t * laneCount). Emit per-lane energies + a transparent yellow overlay.
///
/// Coordinate convention: normalized coords (0..1) are top-left-origin (y=0 at top), matching
/// SwiftUI / `PlayerViewModel.finishLineTopX/BottomX`.
enum MotionInspector {

    /// Baselines close in time so inter-frame motion of the boat (paddle stroke + bow advance)
    /// reliably differs from baseline. Long-window baselines (-1s+) often already contain the
    /// boat in nearly the same position when it travels slowly relative to ROI width.
    static let defaultBaselineDeltas: [Double] = [-0.10, -0.18, -0.28]

    // MARK: - Live inspection

    /// Convenience wrapper accepting a `DetectionLine`.
    static func motionAnalysis(
        currentFrame: CGImage,
        baselines: [CGImage],
        line: DetectionLine,
        threshold: Int
    ) -> MotionAnalysisResult {
        return motionAnalysis(
            currentFrame: currentFrame,
            baselines: baselines,
            normalizedP1: line.p1,
            normalizedP2: line.p2,
            roiHalfWidthPx: line.roiHalfWidthPx,
            threshold: threshold,
            tStart: 0, tEnd: 1
        )
    }

    /// Core implementation — accepts raw normalized points so callers can use either the
    /// photo-finish line (top-edge → bottom-edge) or a free-form detection line.
    /// `tStart`/`tEnd` (0..1) clip the analysis to a sub-segment along the line, useful
    /// to exclude shore/sky regions from a full-height line.
    static func motionAnalysis(
        currentFrame: CGImage,
        baselines: [CGImage],
        normalizedP1: CGPoint,
        normalizedP2: CGPoint,
        roiHalfWidthPx: Int,
        threshold: Int,
        tStart: Double = 0,
        tEnd: Double = 1
    ) -> MotionAnalysisResult {
        guard !baselines.isEmpty else {
            return MotionAnalysisResult(overlay: nil, energy: 0, centroidOffsetAlongLine: 0)
        }

        let w = currentFrame.width
        let h = currentFrame.height
        let pp1 = CGPoint(x: normalizedP1.x * CGFloat(w), y: normalizedP1.y * CGFloat(h))
        let pp2 = CGPoint(x: normalizedP2.x * CGFloat(w), y: normalizedP2.y * CGFloat(h))
        let dx = pp2.x - pp1.x
        let dy = pp2.y - pp1.y
        let lineLen = hypot(dx, dy)
        guard lineLen > 1 else {
            return MotionAnalysisResult(overlay: nil, energy: 0, centroidOffsetAlongLine: 0)
        }
        let ux = dx / lineLen, uy = dy / lineLen
        let rHalf = roiHalfWidthPx

        let minX = max(0, Int(floor(min(pp1.x, pp2.x))) - rHalf)
        let maxX = min(w - 1, Int(ceil(max(pp1.x, pp2.x))) + rHalf)
        let minY = max(0, Int(floor(min(pp1.y, pp2.y))) - rHalf)
        let maxY = min(h - 1, Int(ceil(max(pp1.y, pp2.y))) + rHalf)
        guard maxX > minX, maxY > minY else {
            return MotionAnalysisResult(overlay: nil, energy: 0, centroidOffsetAlongLine: 0)
        }
        let roiW = maxX - minX + 1
        let roiH = maxY - minY + 1

        guard let curBuf = renderGrayROI(image: currentFrame, x: minX, y: minY, w: roiW, h: roiH) else {
            return MotionAnalysisResult(overlay: nil, energy: 0, centroidOffsetAlongLine: 0)
        }
        var baseBufs: [[UInt8]] = []
        baseBufs.reserveCapacity(baselines.count)
        for b in baselines {
            if let bb = renderGrayROI(image: b, x: minX, y: minY, w: roiW, h: roiH) {
                baseBufs.append(bb)
            }
        }
        guard !baseBufs.isEmpty else {
            return MotionAnalysisResult(overlay: nil, energy: 0, centroidOffsetAlongLine: 0)
        }

        var energy = 0
        var offsetSum = 0.0

        // Full-frame transparent RGBA overlay; only fired pixels are written.
        var overlayBytes = [UInt8](repeating: 0, count: w * h * 4)

        for ry in 0..<roiH {
            let absY = ry + minY
            for rx in 0..<roiW {
                let absX = rx + minX
                let curV = Int(curBuf[ry * roiW + rx])
                var baseSum = 0
                for bb in baseBufs { baseSum += Int(bb[ry * roiW + rx]) }
                let baseMean = baseSum / baseBufs.count
                let diff = abs(curV - baseMean)
                guard diff > threshold else { continue }
                let vx = CGFloat(absX) - pp1.x
                let vy = CGFloat(absY) - pp1.y
                let along = vx * ux + vy * uy
                let perp  = -vx * uy + vy * ux
                guard abs(perp) <= CGFloat(rHalf) else { continue }
                guard along >= 0, along <= lineLen else { continue }
                let t = along / lineLen
                // Clip to the analysis sub-segment (e.g. water-only).
                if Double(t) < tStart || Double(t) > tEnd { continue }
                energy += 1
                offsetSum += Double(t)
                // Splat 3x3 around the fired pixel so single-pixel hits are visible at
                // typical video display scale.
                for sy in -1...1 {
                    let yy = absY + sy
                    if yy < 0 || yy >= h { continue }
                    for sx in -1...1 {
                        let xx = absX + sx
                        if xx < 0 || xx >= w { continue }
                        let off = (yy * w + xx) * 4
                        overlayBytes[off + 0] = 255
                        overlayBytes[off + 1] = 230
                        overlayBytes[off + 2] = 0
                        overlayBytes[off + 3] = 220
                    }
                }
            }
        }

        let centroid = energy > 0 ? offsetSum / Double(energy) : 0.0

        // Always paint the ROI band outline (faint cyan) so the user sees what region is
        // being analyzed, even when nothing fires.
        paintROIOutline(bytes: &overlayBytes, w: w, h: h,
                        pp1: pp1, pp2: pp2, ux: ux, uy: uy, lineLen: lineLen, rHalf: rHalf)

        let overlay = makeRGBAImage(bytes: overlayBytes, width: w, height: h)
        print("[MotionInspector] energy=\(energy) centroid=\(String(format: "%.2f", centroid)) roi=\(roiW)x\(roiH) thr=\(threshold) baselines=\(baseBufs.count)")
        return MotionAnalysisResult(overlay: overlay, energy: energy, centroidOffsetAlongLine: centroid)
    }

    /// Draw a faint cyan ROI outline (4 sides of the rotated rectangle defined by line ± rHalf).
    private static func paintROIOutline(
        bytes: inout [UInt8], w: Int, h: Int,
        pp1: CGPoint, pp2: CGPoint, ux: CGFloat, uy: CGFloat, lineLen: CGFloat, rHalf: Int
    ) {
        let r = CGFloat(rHalf)
        // Perpendicular unit vector (left-hand normal in screen coords)
        let nx = -uy, ny = ux
        let a = CGPoint(x: pp1.x + nx * r, y: pp1.y + ny * r)
        let b = CGPoint(x: pp2.x + nx * r, y: pp2.y + ny * r)
        let c = CGPoint(x: pp2.x - nx * r, y: pp2.y - ny * r)
        let d = CGPoint(x: pp1.x - nx * r, y: pp1.y - ny * r)
        for (s, e) in [(a,b), (b,c), (c,d), (d,a)] {
            drawLine(bytes: &bytes, w: w, h: h, from: s, to: e, rgba: (0, 220, 255, 80))
        }
    }

    /// Naive Bresenham-ish line rasterizer for the overlay outline.
    private static func drawLine(bytes: inout [UInt8], w: Int, h: Int,
                                  from a: CGPoint, to b: CGPoint,
                                  rgba: (UInt8, UInt8, UInt8, UInt8)) {
        let steps = Int(max(abs(b.x - a.x), abs(b.y - a.y)))
        guard steps > 0 else { return }
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = Int(round(a.x + (b.x - a.x) * t))
            let y = Int(round(a.y + (b.y - a.y) * t))
            guard x >= 0, x < w, y >= 0, y < h else { continue }
            let off = (y * w + x) * 4
            bytes[off + 0] = rgba.0
            bytes[off + 1] = rgba.1
            bytes[off + 2] = rgba.2
            bytes[off + 3] = rgba.3
        }
    }

    // MARK: - Full-clip sweep

    /// Walk `asset` from t = max(baselineDeltas) to duration, computing per-lane motion energy
    /// at each sampled frame. `frameStride` of 1 = every frame; 3 = every 3rd frame (faster).
    /// Returns one row per (frame, lane).
    static func sweep(
        asset: AVAsset,
        normalizedP1: CGPoint,
        normalizedP2: CGPoint,
        roiHalfWidthPx: Int,
        threshold: Int,
        tStart: Double = 0,
        tEnd: Double = 1,
        frameStride: Int = 1,
        progress: @escaping (Double) -> Void
    ) async throws -> [SweepRow] {
        let track = asset.tracks(withMediaType: .video).first
        let nominalFps = Double(track?.nominalFrameRate ?? 30.0)
        let frameRate = nominalFps > 0 ? nominalFps : 30.0
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0 else { return [] }

        let stride = max(1, frameStride)
        let frameStep = Double(stride) / frameRate
        // Baselines expressed in samples (integer multiples of frameStep) so each
        // baseline is also a previously-fetched "current" frame — drives ~75% cache hit rate.
        // Keep total temporal span similar to defaultBaselineDeltas (~0.1–0.3s).
        let baselineSampleOffsets: [Int] = [3, 6, 9]
        let firstSampleTime = Double(baselineSampleOffsets.max() ?? 0) * frameStep
        let lastSampleTime = max(firstSampleTime, duration - 0.001)
        let totalSamples = max(1, Int((lastSampleTime - firstSampleTime) / frameStep))

        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.appliesPreferredTrackTransform = true

        // Frame cache keyed by sample index. Bounded — only need to retain frames within
        // the maximum baseline lookback.
        var cache: [Int: CGImage] = [:]
        cache.reserveCapacity(20)
        let maxLookback = baselineSampleOffsets.max() ?? 0

        // Helper: fetch frame at the given sample index, using the cache.
        func frameForSampleIndex(_ idx: Int) -> CGImage? {
            if let cached = cache[idx] { return cached }
            let t = Double(idx) * frameStep
            let cmt = CMTime(seconds: t, preferredTimescale: 600)
            guard let img = try? gen.copyCGImage(at: cmt, actualTime: nil) else { return nil }
            cache[idx] = img
            return img
        }

        var rows: [SweepRow] = []
        rows.reserveCapacity(totalSamples)

        var lastReported = 0.0
        let firstSampleIndex = baselineSampleOffsets.max() ?? 0
        let lastSampleIndex = Int(lastSampleTime / frameStep)
        for sampleIndex in firstSampleIndex...lastSampleIndex {
            try Task.checkCancellation()

            guard let cur = frameForSampleIndex(sampleIndex) else { continue }
            var baselines: [CGImage] = []
            for off in baselineSampleOffsets {
                if let b = frameForSampleIndex(sampleIndex - off) { baselines.append(b) }
            }
            if baselines.isEmpty { continue }

            let result = motionAnalysis(currentFrame: cur, baselines: baselines,
                                        normalizedP1: normalizedP1, normalizedP2: normalizedP2,
                                        roiHalfWidthPx: roiHalfWidthPx, threshold: threshold,
                                        tStart: tStart, tEnd: tEnd)
            let t = Double(sampleIndex) * frameStep
            rows.append(SweepRow(time: t,
                                 motionEnergy: result.energy,
                                 centroidOffsetAlongLine: result.centroidOffsetAlongLine))

            // Evict frames older than the deepest baseline lookback.
            let evictBefore = sampleIndex - maxLookback
            cache = cache.filter { $0.key >= evictBefore }

            let i = sampleIndex - firstSampleIndex
            let pct = min(1.0, Double(i + 1) / Double(totalSamples))
            if pct - lastReported >= 0.01 {
                await MainActor.run { progress(pct) }
                lastReported = pct
            }
        }
        await MainActor.run { progress(1.0) }
        return rows
    }

    /// Find boat-crossing events in the sweep time-series.
    ///
    /// Strategy: smooth raw per-frame energy with an 11-sample rolling mean (~0.37 s at 30 fps)
    /// to suppress paddle-stroke and glare noise, then find peaks of the *smoothed* signal that
    /// rise at least `peakMultiplier` × the global median, separated by at least
    /// `minSeparationSeconds`.
    ///
    /// Defaults are tuned for dragon-boat racing where each boat dwells at the line for
    /// ~1.5–3 s — so two real crossings are rarely closer than 2 s and per-paddler oscillation
    /// (~1 Hz) gets averaged out by the smoother.
    static func detectCrossings(
        rows: [SweepRow],
        peakMultiplier: Double = 2.5,
        minSeparationSeconds: Double = 2.0
    ) -> [CrossingEvent] {
        guard rows.count >= 11 else { return [] }
        let smoothWindow = 11
        let half = smoothWindow / 2

        // Rolling mean
        var smoothed = [Double](repeating: 0, count: rows.count)
        for i in 0..<rows.count {
            let lo = max(0, i - half)
            let hi = min(rows.count - 1, i + half)
            var sum = 0
            for j in lo...hi { sum += rows[j].motionEnergy }
            smoothed[i] = Double(sum) / Double(hi - lo + 1)
        }

        let nonZero = smoothed.filter { $0 > 0.5 }.sorted()
        let median = nonZero.isEmpty ? 0 : nonZero[nonZero.count / 2]
        let cutoff = max(1.0, median * peakMultiplier)

        var crossings: [CrossingEvent] = []
        var lastPeakTime: Double = -.infinity
        for i in half..<(rows.count - half) {
            let e = smoothed[i]
            if e < cutoff { continue }
            // Local max in smoothed signal across ± half-window
            var isLocalMax = true
            for k in 1...half {
                if smoothed[i - k] > e || smoothed[i + k] > e {
                    isLocalMax = false; break
                }
            }
            if !isLocalMax { continue }
            if rows[i].time - lastPeakTime < minSeparationSeconds { continue }
            crossings.append(CrossingEvent(
                time: rows[i].time,
                peakEnergy: rows[i].motionEnergy,           // report raw energy at peak
                centroidOffsetAlongLine: rows[i].centroidOffsetAlongLine
            ))
            lastPeakTime = rows[i].time
        }
        return crossings
    }

    // MARK: - Helpers

    /// Render a sub-rect of `image` into an 8-bit grayscale buffer, top-left-origin.
    private static func renderGrayROI(image: CGImage, x: Int, y: Int, w: Int, h: Int) -> [UInt8]? {
        guard w > 0, h > 0 else { return nil }
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else { return nil }
        let cs = CGColorSpaceCreateDeviceGray()
        var bytes = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = bytes.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w,
                                      space: cs,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // Flip so source's top row lands at our buffer row 0 (top-left origin).
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? bytes : nil
    }

    private static func makeRGBAImage(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: cs,
                       bitmapInfo: bitmapInfo, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
