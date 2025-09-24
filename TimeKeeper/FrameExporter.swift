import AVFoundation
import AppKit
import UniformTypeIdentifiers

class FrameExporter {
    func exportFrame(from videoURL: URL, at time: Double, to outputURL: URL, zeroTolerance: Bool = false, jpegQuality: Double = 0.92, completion: @escaping (Bool) -> Void) {
        let asset = AVAsset(url: videoURL)

        Task {
            await exportJPEG(
                assetURL: videoURL,
                at: time,
                exact: zeroTolerance,
                jpegQuality: jpegQuality,
                outURL: outputURL,
                completion: completion
            )
        }
    }

    private func exportJPEG(assetURL: URL, at seconds: Double, exact: Bool, jpegQuality: Double, outURL: URL, completion: @escaping (Bool) -> Void) async {
        let asset = AVAsset(url: assetURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)

        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = .zero

        if exact {
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero
        }

        let time = CMTime(seconds: seconds, preferredTimescale: 600)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)

            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            let jpegData = bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: NSNumber(value: jpegQuality)]
            )

            if let data = jpegData {
                try data.write(to: outURL)
                DispatchQueue.main.async {
                    completion(true)
                    NSWorkspace.shared.selectFile(outURL.path, inFileViewerRootedAtPath: outURL.deletingLastPathComponent().path)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        } catch {
            print("Error exporting frame: \(error)")
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
}