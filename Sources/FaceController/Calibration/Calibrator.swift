import Foundation

/// The outcome of a calibration: your "neutral" (relaxed, looking straight) face.
struct CalibrationResult: Equatable {
    /// Neutral head angles. Every head gesture is measured relative to these.
    let neutral: HeadAngles
    /// Neutral mouth/eyebrows. nil if the landmarks couldn't be read during calibration.
    let neutralExpressions: ExpressionValues?

    /// How much each value wobbled while you held still (standard deviation).
    /// Small = good. Compare these with the thresholds: a value whose jitter is close
    /// to its press threshold will cause false triggers.
    let pitchJitter: Double
    let yawJitter: Double
    let mouthJitter: Double?
    let browJitter: Double?

    let sampleCount: Int
}

/// Records your neutral face while you look straight at the camera.
///
/// - Only counts time while a face is visible. If you look away, the timer pauses.
/// - Uses the MEDIAN of all samples (the middle value), which ignores the odd
///   bad frame much better than an average would.
struct Calibrator {
    private(set) var isCollecting = false
    /// Whether a face was visible in the most recent frame during calibration.
    private(set) var faceVisible = false

    private var angleSamples: [HeadAngles] = []
    private var expressionSamples: [ExpressionValues] = []
    private var collectedTime: Double = 0
    private var lastSampleTime: Double?

    /// Need at least this many expression samples to trust the neutral mouth/eyebrows.
    private let minimumSamples = 10

    /// 0...1 progress through the calibration.
    var progress: Double {
        min(1, collectedTime / Config.Calibration.duration)
    }

    /// Starts (or restarts) recording.
    mutating func start() {
        isCollecting = true
        faceVisible = false
        angleSamples.removeAll(keepingCapacity: true)
        expressionSamples.removeAll(keepingCapacity: true)
        collectedTime = 0
        lastSampleTime = nil
    }

    /// Adds one frame. Returns the result once enough time has been recorded.
    mutating func addSample(_ angles: HeadAngles,
                            expressions: ExpressionValues?,
                            at time: Double) -> CalibrationResult? {
        guard isCollecting else { return nil }
        faceVisible = true

        if let last = lastSampleTime {
            // Count the time since the previous face frame (capped, so a frozen
            // camera can't suddenly "complete" calibration in one jump).
            collectedTime += min(max(time - last, 0), 0.1)
        }
        lastSampleTime = time
        angleSamples.append(angles)
        if let expressions = expressions {
            expressionSamples.append(expressions)
        }

        guard collectedTime >= Config.Calibration.duration, angleSamples.count >= minimumSamples else {
            return nil
        }
        isCollecting = false

        let neutral = HeadAngles(pitch: Self.median(angleSamples.map { $0.pitch }),
                                 yaw: Self.median(angleSamples.map { $0.yaw }),
                                 roll: Self.median(angleSamples.map { $0.roll }))

        var neutralExpressions: ExpressionValues?
        var mouthJitter: Double?
        var browJitter: Double?
        if expressionSamples.count >= minimumSamples {
            let mouth = expressionSamples.map { $0.mouthOpen }
            let brow = expressionSamples.map { $0.browHeight }
            neutralExpressions = ExpressionValues(mouthOpen: Self.median(mouth),
                                                  browHeight: Self.median(brow))
            mouthJitter = Self.standardDeviation(mouth)
            browJitter = Self.standardDeviation(brow)
        }

        return CalibrationResult(neutral: neutral,
                                 neutralExpressions: neutralExpressions,
                                 pitchJitter: Self.standardDeviation(angleSamples.map { $0.pitch }),
                                 yawJitter: Self.standardDeviation(angleSamples.map { $0.yaw }),
                                 mouthJitter: mouthJitter,
                                 browJitter: browJitter,
                                 sampleCount: angleSamples.count)
    }

    /// Call when a frame has no face: pauses the calibration timer.
    mutating func faceMissing() {
        faceVisible = false
        lastSampleTime = nil
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }
}
