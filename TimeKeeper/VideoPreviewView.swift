import SwiftUI
import AVFoundation
import AppKit

struct VideoPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    class VideoPreviewNSView: NSView {
        private var previewLayer: AVCaptureVideoPreviewLayer?
        var session: AVCaptureSession

        init(session: AVCaptureSession) {
            self.session = session
            super.init(frame: .zero)
            setupLayer()
        }

        func setupLayer() {
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor

            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspect
            previewLayer?.frame = bounds
            previewLayer?.connection?.automaticallyAdjustsVideoMirroring = false

            if let previewLayer = previewLayer {
                layer?.addSublayer(previewLayer)
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }

    func makeNSView(context: Context) -> VideoPreviewNSView {
        return VideoPreviewNSView(session: session)
    }

    func updateNSView(_ nsView: VideoPreviewNSView, context: Context) {
        // Updates handled by the preview layer automatically
    }
}