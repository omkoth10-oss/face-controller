import Vision
import CoreVideo
import CoreGraphics

/// Head rotation in DEGREES, as Vision measures it in the camera image.
/// (For directions from the player's point of view, see PlayerDirections.)
/// - pitch: nodding (up / down)
/// - yaw:   turning (left / right)
/// - roll:  tilting toward a shoulder
struct HeadAngles: Equatable {
    var pitch: Double
    var yaw: Double
    var roll: Double

    static let zero = HeadAngles(pitch: 0, yaw: 0, roll: 0)

    static func - (lhs: HeadAngles, rhs: HeadAngles) -> HeadAngles {
        HeadAngles(pitch: lhs.pitch - rhs.pitch, yaw: lhs.yaw - rhs.yaw, roll: lhs.roll - rhs.roll)
    }
}

/// What Vision found in one camera frame.
struct FaceMeasurement {
    /// Raw head angles straight from Vision (degrees, not smoothed, not calibrated).
    let angles: HeadAngles
    /// Mouth and eyebrow measurements, or nil if the landmarks couldn't be read this frame.
    let expressions: ExpressionValues?
    /// How sure Vision is that this is a face (0...1).
    let confidence: Float
    /// Where the face is in the image (0...1 coordinates, origin at bottom-left).
    let boundingBox: CGRect
}

/// Result of analyzing one frame.
enum TrackingResult {
    /// A face with head angles.
    case face(FaceMeasurement)
    /// No face in this frame.
    case noFace
    /// A face was found but Vision didn't report the head angles
    /// (shouldn't happen on macOS 13+, but we handle it instead of guessing).
    case faceWithoutAngles
}

/// Uses Apple's Vision framework to find the face in a frame and measure it.
///
/// Two Vision requests per frame, run back to back:
/// 1. `VNDetectFaceRectanglesRequest` (revision 3): finds the face and gives smooth,
///    continuous pitch / yaw / roll. This is Vision's fastest face request.
/// 2. `VNDetectFaceLandmarksRequest`: given THAT face (so it doesn't search the
///    image again), finds ~76 points outlining the eyes, eyebrows, lips, etc.
///    ExpressionReader turns those into "mouth open" and "eyebrows raised".
final class HeadPoseTracker {

    /// Created once and reused for every frame (cheaper than making new ones each time).
    private let faceRequest: VNDetectFaceRectanglesRequest
    private let landmarksRequest: VNDetectFaceLandmarksRequest

    /// How long the landmarks step took on the last frame (seconds), for the debug window.
    private(set) var lastLandmarksDuration: Double?

    init() {
        faceRequest = VNDetectFaceRectanglesRequest()
        // Ask for revision 3 explicitly (if this macOS has it) so behavior doesn't
        // silently change when Apple adds a new revision.
        if VNDetectFaceRectanglesRequest.supportedRevisions.contains(VNDetectFaceRectanglesRequestRevision3) {
            faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        }

        landmarksRequest = VNDetectFaceLandmarksRequest()
        if VNDetectFaceLandmarksRequest.supportedRevisions.contains(VNDetectFaceLandmarksRequestRevision3) {
            landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
            // The detailed 76-point outline (revision 3 only).
            landmarksRequest.constellation = .constellation76Points
        }
    }

    /// Runs Vision on one frame. Call this from the tracking queue only.
    func analyze(_ pixelBuffer: CVPixelBuffer) throws -> TrackingResult {
        lastLandmarksDuration = nil

        // Mac cameras deliver upright landscape frames, so orientation is `.up`.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([faceRequest])

        let faces = (faceRequest.results ?? [])
            .filter { $0.confidence >= Config.Tracking.minimumFaceConfidence }

        // If several people are in view, follow the biggest (closest) face.
        guard let face = faces.max(by: { area($0.boundingBox) < area($1.boundingBox) }) else {
            return .noFace
        }
        guard let pitch = face.pitch?.doubleValue else {
            return .faceWithoutAngles
        }
        // Vision reports radians; degrees are easier for people to read and tune.
        let angles = HeadAngles(pitch: degrees(pitch),
                                yaw: degrees(face.yaw?.doubleValue ?? 0),
                                roll: degrees(face.roll?.doubleValue ?? 0))

        var expressions: ExpressionValues?
        if Config.Tracking.expressionsEnabled {
            expressions = readExpressions(of: face, handler: handler, pixelBuffer: pixelBuffer)
        }

        return .face(FaceMeasurement(angles: angles,
                                     expressions: expressions,
                                     confidence: face.confidence,
                                     boundingBox: face.boundingBox))
    }

    /// Runs the landmarks request on the face we already found.
    /// A landmarks failure only loses the expressions for this frame; head tracking continues.
    private func readExpressions(of face: VNFaceObservation,
                                 handler: VNImageRequestHandler,
                                 pixelBuffer: CVPixelBuffer) -> ExpressionValues? {
        let start = HostClock.now()
        defer { lastLandmarksDuration = HostClock.now() - start }

        landmarksRequest.inputFaceObservations = [face]
        do {
            try handler.perform([landmarksRequest])
        } catch {
            return nil
        }
        guard let landmarks = landmarksRequest.results?.first?.landmarks else { return nil }
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer))
        return ExpressionReader.read(landmarks, imageSize: imageSize)
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
    private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
