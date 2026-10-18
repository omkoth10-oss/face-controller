import AVFoundation
import CoreMedia

/// What camera we ended up with (shown in the debug window).
struct CameraInfo {
    let deviceName: String
    let width: Int32
    let height: Int32
    let frameRate: Double
    /// Extra explanation, e.g. "60 fps isn't supported by this camera, using 30".
    let note: String?
}

enum CameraError: Error {
    case noCamera
    case cannotOpen(String)
    case cannotAddInput
    case cannotAddOutput

    var message: String {
        switch self {
        case .noCamera:
            return "No camera found. Plug in a webcam or check that the built-in camera works in Photo Booth."
        case .cannotOpen(let details):
            return "Couldn't open the camera: \(details). Is another app using it, or is Camera permission off?"
        case .cannotAddInput:
            return "Couldn't connect to the camera (it may be in use by another app)."
        case .cannotAddOutput:
            return "Couldn't set up the camera video output."
        }
    }
}

/// Owns the camera (AVFoundation) and delivers every frame to `onFrame`.
///
/// How it works, in plain language:
/// - An `AVCaptureSession` connects the camera (input) to a video data output.
/// - The output hands us each frame on `frameQueue`, a background queue, so
///   heavy work never blocks the window.
/// - `alwaysDiscardsLateVideoFrames = true` means: if we're still busy with the
///   previous frame when a new one arrives, the new one is DROPPED instead of
///   waiting in a line. Waiting in line would add latency; dropping keeps us
///   working on the freshest frame.
final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Shared with the camera preview in the debug window.
    let session = AVCaptureSession()

    /// Setting up and starting the camera can take ~1 second, so it runs on its
    /// own queue to keep the window responsive.
    private let sessionQueue = DispatchQueue(label: "FaceController.camera-setup")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameQueue: DispatchQueue
    private let onFrame: (CMSampleBuffer) -> Void
    private let onDroppedFrame: () -> Void

    private var device: AVCaptureDevice?
    private var chosenFormat: FormatChoice?
    private var isConfigured = false

    /// - Parameters:
    ///   - frameQueue: serial queue that receives frames (the tracking loop's queue).
    ///   - onFrame: called for every frame, on `frameQueue`.
    ///   - onDroppedFrame: called when AVFoundation dropped a late frame, on `frameQueue`.
    init(frameQueue: DispatchQueue,
         onFrame: @escaping (CMSampleBuffer) -> Void,
         onDroppedFrame: @escaping () -> Void) {
        self.frameQueue = frameQueue
        self.onFrame = onFrame
        self.onDroppedFrame = onDroppedFrame
        super.init()
    }

    // MARK: - Start

    /// Configures (first time only) and starts the camera.
    /// `completion` is called on a background queue.
    func start(completion: @escaping (Result<CameraInfo, CameraError>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }
                if !self.session.isRunning {
                    self.session.startRunning()  // Blocks until the camera is running.
                }
                self.reapplyFormatIfReset()
                completion(.success(self.currentInfo()))
            } catch let error as CameraError {
                completion(.failure(error))
            } catch {
                completion(.failure(.cannotOpen(error.localizedDescription)))
            }
        }
    }

    // MARK: - Frame delivery (AVCaptureVideoDataOutputSampleBufferDelegate)

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onFrame(sampleBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onDroppedFrame()
    }

    // MARK: - Setup

    private func configureSession() throws {
        session.beginConfiguration()
        // `defer` runs when this function exits, even if we throw an error,
        // so the session is never left half-configured.
        defer { session.commitConfiguration() }

        guard let device = Self.findCamera() else { throw CameraError.noCamera }
        self.device = device

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.cannotOpen(error.localizedDescription)
        }
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        // Drop late frames instead of queueing them (see the explanation at the top).
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // Ask for the camera's native YUV format (cheap: no color conversion needed).
        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        if videoOutput.availableVideoPixelFormatTypes.contains(pixelFormat) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        }

        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        // Pick the camera mode (resolution + frame rate). This must happen AFTER the
        // input is added to the session, otherwise the session overrides it.
        if let choice = Self.chooseFormat(for: device) {
            chosenFormat = choice
            Self.apply(choice, to: device)
        }
    }

    /// On some Macs the session resets the camera mode when it starts.
    /// If that happened, set our chosen mode again.
    private func reapplyFormatIfReset() {
        guard let device = device, let choice = chosenFormat else { return }
        let formatChanged = device.activeFormat != choice.format
        let rateChanged = CMTimeCompare(device.activeVideoMinFrameDuration, choice.frameDuration) != 0
        if formatChanged || rateChanged {
            Self.apply(choice, to: device)
        }
    }

    /// Reads back what the camera is ACTUALLY doing (not just what we asked for).
    private func currentInfo() -> CameraInfo {
        guard let device = device else {
            return CameraInfo(deviceName: "Unknown", width: 0, height: 0, frameRate: 0, note: nil)
        }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let duration = device.activeVideoMinFrameDuration
        let fps = (duration.isValid && duration.seconds > 0) ? 1.0 / duration.seconds : 0

        var note: String?
        if fps < Config.Camera.preferredFrameRate - 1 {
            note = "This camera can't do \(Int(Config.Camera.preferredFrameRate)) fps at a usable resolution, so it's using its fastest rate."
        }
        return CameraInfo(deviceName: device.localizedName,
                          width: dims.width,
                          height: dims.height,
                          frameRate: fps,
                          note: note)
    }

    // MARK: - Choosing the camera and its mode

    /// The front (built-in FaceTime) camera if there is one, otherwise the system default camera.
    private static func findCamera() -> AVCaptureDevice? {
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return front
        }
        if let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) {
            return builtIn
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// One camera mode we could use.
    private struct FormatChoice {
        let format: AVCaptureDevice.Format
        let frameDuration: CMTime  // Time between frames (1/60 s for 60 fps).
        let frameRate: Double
        let width: Int32
        let height: Int32
    }

    /// Looks through every mode the camera supports and picks the best one:
    /// 1. Highest frame rate (up to 60), because that matters most for latency.
    /// 2. Then the resolution closest to 640x480 (smaller = faster to process).
    private static func chooseFormat(for device: AVCaptureDevice) -> FormatChoice? {
        var best: FormatChoice?
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= Config.Camera.minimumWidth,
                  dims.height >= Config.Camera.minimumHeight,
                  dims.width <= Config.Camera.maximumWidth else { continue }
            guard let rate = bestFrameRate(for: format) else { continue }

            let candidate = FormatChoice(format: format,
                                         frameDuration: rate.duration,
                                         frameRate: rate.fps,
                                         width: dims.width,
                                         height: dims.height)
            if let current = best, !isBetter(candidate, than: current) { continue }
            best = candidate
        }
        return best
    }

    private static func isBetter(_ a: FormatChoice, than b: FormatChoice) -> Bool {
        if abs(a.frameRate - b.frameRate) > 1 {
            return a.frameRate > b.frameRate
        }
        return distanceFromPreferredSize(a) < distanceFromPreferredSize(b)
    }

    private static func distanceFromPreferredSize(_ choice: FormatChoice) -> Int64 {
        let pixels = Int64(choice.width) * Int64(choice.height)
        let preferred = Int64(Config.Camera.preferredWidth) * Int64(Config.Camera.preferredHeight)
        return abs(pixels - preferred)
    }

    /// The fastest frame rate this mode supports, capped at our preferred rate.
    private static func bestFrameRate(for format: AVCaptureDevice.Format) -> (fps: Double, duration: CMTime)? {
        let target = Config.Camera.preferredFrameRate
        var best: (fps: Double, duration: CMTime)?
        for range in format.videoSupportedFrameRateRanges {
            let candidate: (fps: Double, duration: CMTime)
            if range.maxFrameRate <= target + 0.5 {
                // The camera's fastest rate in this range is at (or below) our target:
                // use exactly the camera's own fastest value so it's always valid.
                candidate = (range.maxFrameRate, range.minFrameDuration)
            } else if range.minFrameRate <= target {
                // The range goes faster than our target but includes it: use the target.
                candidate = (target, CMTime(value: 1, timescale: CMTimeScale(target)))
            } else {
                continue  // Only faster-than-target rates; skip.
            }
            if let current = best, current.fps >= candidate.fps { continue }
            best = candidate
        }
        return best
    }

    /// Switches the camera to the chosen mode and locks its frame rate.
    ///
    /// Locking both the minimum and maximum frame duration to the same value stops
    /// the camera from quietly slowing down in dim light (which would add latency).
    private static func apply(_ choice: FormatChoice, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
        } catch {
            return  // Keep the camera's default mode.
        }
        defer { device.unlockForConfiguration() }

        device.activeFormat = choice.format

        // The minimum duration must never be larger than the maximum, so set them
        // in an order that keeps that true at every step.
        let duration = choice.frameDuration
        if CMTimeCompare(duration, device.activeVideoMaxFrameDuration) > 0 {
            device.activeVideoMaxFrameDuration = duration
            device.activeVideoMinFrameDuration = duration
        } else {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }
}
