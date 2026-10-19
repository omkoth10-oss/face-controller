import CoreGraphics
import Vision

/// Facial expression measurements for one frame.
///
/// Both are in PERCENT of the distance between your eyes. Using the eye distance as
/// a ruler means the numbers stay the same whether you sit close to the camera or far.
struct ExpressionValues: Equatable {
    /// Gap between the inner edges of the lips. Near 0 with the mouth closed.
    var mouthOpen: Double
    /// Height of the eyebrows above the eye corners (average of both sides).
    var browHeight: Double
}

/// Turns Vision's face landmarks (dots outlining the eyes, brows, lips...) into
/// expression numbers.
///
/// How it works, in plain language:
/// 1. Find the line through both eyes. "Up" for the face is perpendicular to it.
///    Measuring along the face's own "up" means tilting your head sideways (roll)
///    doesn't change the numbers.
/// 2. For each eye, use the midpoint of its two CORNERS as the reference point.
///    Eye corners don't move when you blink (the eyelids do), so blinking doesn't
///    look like raising your eyebrows.
/// 3. Mouth open = top-to-bottom size of the inner lip outline.
///    Eyebrows = how far each eyebrow's center sits above its eye's corner midpoint.
/// 4. Divide by the distance between the eyes and multiply by 100.
enum ExpressionReader {

    static func read(_ landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> ExpressionValues? {
        guard let leftEye = landmarks.leftEye?.pointsInImage(imageSize: imageSize),
              let rightEye = landmarks.rightEye?.pointsInImage(imageSize: imageSize),
              let leftBrow = landmarks.leftEyebrow?.pointsInImage(imageSize: imageSize),
              let rightBrow = landmarks.rightEyebrow?.pointsInImage(imageSize: imageSize),
              let innerLips = landmarks.innerLips?.pointsInImage(imageSize: imageSize),
              leftEye.count >= 2, rightEye.count >= 2,
              !leftBrow.isEmpty, !rightBrow.isEmpty, innerLips.count >= 2 else {
            return nil
        }

        // 1. Rough eye line from the eye centers (only used to find the corners).
        let roughAxis = normalized(centroid(rightEye) - centroid(leftEye))
        guard roughAxis != .zero else { return nil }

        // 2. Eye corner midpoints: stable reference points that ignore blinking.
        let leftRef = cornerMidpoint(leftEye, along: roughAxis)
        let rightRef = cornerMidpoint(rightEye, along: roughAxis)
        let eyeDistance = length(rightRef - leftRef)
        guard eyeDistance > 1 else { return nil }

        // The face's own "up" direction: perpendicular to the eye line...
        let axis = normalized(rightRef - leftRef)
        var up = CGPoint(x: -axis.y, y: axis.x)
        // ...pointing from the mouth toward the eyes (whatever the image's y direction is).
        let eyesMid = midpoint(leftRef, rightRef)
        if dot(eyesMid - centroid(innerLips), up) < 0 {
            up = CGPoint(x: -up.x, y: -up.y)
        }

        // 3a. Mouth: top-to-bottom extent of the inner lips along "up".
        let lipHeights = innerLips.map { dot($0, up) }
        guard let lipTop = lipHeights.max(), let lipBottom = lipHeights.min() else { return nil }
        let mouthGap = lipTop - lipBottom

        // 3b. Eyebrows: each brow's center above its own eye's corner midpoint.
        let leftBrowHeight = dot(centroid(leftBrow) - leftRef, up)
        let rightBrowHeight = dot(centroid(rightBrow) - rightRef, up)
        let browHeight = (leftBrowHeight + rightBrowHeight) / 2

        // 4. In % of the eye distance.
        return ExpressionValues(mouthOpen: Double(mouthGap / eyeDistance) * 100,
                                browHeight: Double(browHeight / eyeDistance) * 100)
    }

    // MARK: - Small geometry helpers (points used as 2D vectors)

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Midpoint of the two points furthest apart along `axis` (the eye's corners).
    private static func cornerMidpoint(_ points: [CGPoint], along axis: CGPoint) -> CGPoint {
        guard let first = points.min(by: { dot($0, axis) < dot($1, axis) }),
              let last = points.max(by: { dot($0, axis) < dot($1, axis) }) else {
            return centroid(points)
        }
        return midpoint(first, last)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }

    private static func length(_ v: CGPoint) -> CGFloat {
        (v.x * v.x + v.y * v.y).squareRoot()
    }

    private static func normalized(_ v: CGPoint) -> CGPoint {
        let len = length(v)
        return len > 0 ? CGPoint(x: v.x / len, y: v.y / len) : .zero
    }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}
