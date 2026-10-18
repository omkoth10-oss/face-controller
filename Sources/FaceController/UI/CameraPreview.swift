import AVFoundation
import AppKit
import QuartzCore
import SwiftUI

/// Live camera picture for the debug window.
///
/// It uses `AVCaptureVideoPreviewLayer`, which draws the camera feed directly on the
/// GPU. It's separate from the tracking loop, so showing the preview doesn't slow
/// tracking down. SwiftUI can't show a CALayer by itself, so we wrap it in an
/// NSView (`NSViewRepresentable` is SwiftUI's adapter for AppKit views).
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.applyMirroringIfPossible()
    }
}

final class PreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var mirroringApplied = false

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("PreviewView is only created in code")
    }

    override func layout() {
        super.layout()
        // Resize the video layer with the view, without the default fade animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
        applyMirroringIfPossible()
    }

    /// Show the picture mirrored, like a real mirror (and like FaceTime / Photo Booth).
    /// Only the PREVIEW is mirrored; tracking uses the original frames.
    func applyMirroringIfPossible() {
        guard !mirroringApplied,
              let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
        mirroringApplied = true
    }
}
