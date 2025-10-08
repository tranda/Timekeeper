import AVFoundation
import AppKit
import UniformTypeIdentifiers
import CoreGraphics

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

    func captureFrameData(from videoURL: URL, at time: Double, zeroTolerance: Bool = true, jpegQuality: Double = 0.92, completion: @escaping (Data?) -> Void) {
        Task {
            await captureJPEGData(
                assetURL: videoURL,
                at: time,
                exact: zeroTolerance,
                jpegQuality: jpegQuality,
                completion: completion
            )
        }
    }

    private func captureJPEGData(assetURL: URL, at seconds: Double, exact: Bool, jpegQuality: Double, completion: @escaping (Data?) -> Void) async {
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

            DispatchQueue.main.async {
                completion(jpegData)
            }
        } catch {
            print("Error capturing frame data: \(error)")
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    func exportFrameWithFinishLine(from videoURL: URL, at time: Double, to outputURL: URL, topX: Double, bottomX: Double, videoSize: CGSize, uiHeightScale: Double = 0.9, zeroTolerance: Bool = true, jpegQuality: Double = 0.92, completion: @escaping (Bool) -> Void) {
        Task {
            await exportJPEGWithFinishLine(
                assetURL: videoURL,
                at: time,
                topX: topX,
                bottomX: bottomX,
                videoSize: videoSize,
                uiHeightScale: uiHeightScale,
                exact: zeroTolerance,
                jpegQuality: jpegQuality,
                outURL: outputURL,
                completion: completion
            )
        }
    }

    private func exportJPEGWithFinishLine(assetURL: URL, at seconds: Double, topX: Double, bottomX: Double, videoSize: CGSize, uiHeightScale: Double, exact: Bool, jpegQuality: Double, outURL: URL, completion: @escaping (Bool) -> Void) async {
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

            // Debug logging
            print("=== PHOTO FINISH EXPORT DEBUG ===")
            print("Passed videoSize: \(videoSize)")
            print("Actual image size: \(cgImage.width) x \(cgImage.height)")
            print("Normalized topX: \(topX), bottomX: \(bottomX)")

            // Check if there's a difference between passed size and actual image
            let scaleX = Double(cgImage.width) / Double(videoSize.width)
            let scaleY = Double(cgImage.height) / Double(videoSize.height)
            print("Scale factors - X: \(scaleX), Y: \(scaleY)")
            print("==================================")

            // Create context to draw finish line overlay
            let width = cgImage.width
            let height = cgImage.height
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            // Draw the original frame
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            // Direct coordinate mapping - no margins, no scaling
            // UI: Y=0 (top) to Y=height (bottom)
            // Core Graphics: Y=0 (bottom) to Y=height (top) - coordinates are flipped
            let lineTopY = Double(height)  // UI top edge -> CG top (Y=height)
            let lineBottomY = 0.0          // UI bottom edge -> CG bottom (Y=0)
            let lineTopX = Double(width) * topX
            let lineBottomX = Double(width) * bottomX

            // Use sizes that match the UI overlay appearance exactly
            let lineThickness = 1.0 // UI uses lineWidth: 1
            let handleSize = 16.0 // Fixed handle size similar to UI

            // Debug logging for calculated positions
            print("Calculated positions:")
            print("  lineTopX: \(lineTopX), lineTopY: \(lineTopY)")
            print("  lineBottomX: \(lineBottomX), lineBottomY: \(lineBottomY)")
            print("  lineThickness: \(lineThickness), handleSize: \(handleSize)")

            context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)) // Red line
            context.setLineWidth(CGFloat(lineThickness))
            context.move(to: CGPoint(x: lineTopX, y: lineTopY))
            context.addLine(to: CGPoint(x: lineBottomX, y: lineBottomY))
            context.strokePath()

            // Draw handles with proper scaling
            context.setFillColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)) // Red handles
            let halfHandle = handleSize / 2.0
            context.fillEllipse(in: CGRect(x: lineTopX - halfHandle, y: lineTopY - halfHandle, width: handleSize, height: handleSize))
            context.fillEllipse(in: CGRect(x: lineBottomX - halfHandle, y: lineBottomY - halfHandle, width: handleSize, height: handleSize))


            // Create final image
            guard let finalImage = context.makeImage() else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let bitmapRep = NSBitmapImageRep(cgImage: finalImage)
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
            print("Error exporting frame with finish line: \(error)")
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
}
