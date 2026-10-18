import Vision
import CoreVideo
import CoreGraphics

/// Head rotation in DEGREES.
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

/// Uses Apple's Vision framework to find the face in a frame and read its head angles.
///
/// We use `VNDetectFaceRectanglesRequest` (revision 3), Vision's fastest face request.
/// Revision 3 reports pitch, yaw and roll as smooth continuous values
/// (older revisions only reported coarse 45° steps and no pitch).
/// Face landmarks (eyes, mouth, eyebrows) aren't needed until Phase 2.
final class HeadPoseTracker {

    /// Created once and reused for every frame (cheaper than making a new one each time).
    private let faceRequest: VNDetectFaceRectanglesRequest

    init() {
        faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
    }

    /// Runs Vision on one frame. Call this from the tracking queue only.
    func analyze(_ pixelBuffer: CVPixelBuffer) throws -> TrackingResult {
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
        return .face(FaceMeasurement(angles: angles,
                                     confidence: face.confidence,
                                     boundingBox: face.boundingBox))
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
    private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
