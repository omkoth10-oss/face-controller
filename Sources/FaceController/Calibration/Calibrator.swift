import Foundation

/// The outcome of a calibration: your "neutral" (relaxed, looking straight) head position.
struct CalibrationResult: Equatable {
    /// Neutral head angles. Every gesture is measured relative to these.
    let neutral: HeadAngles
    /// How much your pitch wobbled while calibrating (standard deviation, degrees).
    /// Small (under ~2°) = a good calibration.
    let pitchJitter: Double
    let sampleCount: Int
}

/// Records your neutral head position while you look straight at the camera.
///
/// - Only counts time while a face is visible. If you look away, the timer pauses.
/// - Uses the MEDIAN of all samples (the middle value), which ignores the odd
///   bad frame much better than an average would.
struct Calibrator {
    private(set) var isCollecting = false
    /// Whether a face was visible in the most recent frame during calibration.
    private(set) var faceVisible = false

    private var samples: [HeadAngles] = []
    private var collectedTime: Double = 0
    private var lastSampleTime: Double?

    /// 0...1 progress through the calibration.
    var progress: Double {
        min(1, collectedTime / Config.Calibration.duration)
    }

    /// Starts (or restarts) recording.
    mutating func start() {
        isCollecting = true
        faceVisible = false
        samples.removeAll(keepingCapacity: true)
        collectedTime = 0
        lastSampleTime = nil
    }

    mutating func cancel() {
        isCollecting = false
    }

    /// Adds one frame's head angles. Returns the result once enough time has been recorded.
    mutating func addSample(_ angles: HeadAngles, at time: Double) -> CalibrationResult? {
        guard isCollecting else { return nil }
        faceVisible = true

        if let last = lastSampleTime {
            // Count the time since the previous face frame (capped, so a frozen
            // camera can't suddenly "complete" calibration in one jump).
            collectedTime += min(max(time - last, 0), 0.1)
        }
        lastSampleTime = time
        samples.append(angles)

        guard collectedTime >= Config.Calibration.duration, samples.count >= 10 else { return nil }

        isCollecting = false
        let neutral = HeadAngles(pitch: Self.median(samples.map { $0.pitch }),
                                 yaw: Self.median(samples.map { $0.yaw }),
                                 roll: Self.median(samples.map { $0.roll }))
        return CalibrationResult(neutral: neutral,
                                 pitchJitter: Self.standardDeviation(samples.map { $0.pitch }),
                                 sampleCount: samples.count)
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
