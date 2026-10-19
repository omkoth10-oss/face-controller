import Foundation

/// The "One Euro filter": a tiny, well-known smoothing filter for noisy live signals.
///
/// Problem: Vision's angles jitter by a degree or so every frame. Normal smoothing
/// (averaging) removes jitter but also adds lag, which is bad for games.
///
/// Trick: the One Euro filter changes how much it smooths based on SPEED.
/// - Head still   -> heavy smoothing (jitter disappears, lag doesn't matter).
/// - Head moving  -> very light smoothing (almost no lag when you actually gesture).
///
/// Paper: Casiez, Roussel & Vogel, "1€ Filter" (CHI 2012).
struct OneEuroFilter {
    /// Smoothing strength at rest, in Hz. Lower = smoother but laggier.
    var minCutoff: Double
    /// How much faster movement reduces smoothing.
    var beta: Double
    /// Smoothing for the internal speed estimate.
    var derivativeCutoff: Double

    private var previousValue: Double?
    private var previousSpeed: Double = 0
    private var previousTime: Double?

    init(minCutoff: Double = Config.Smoothing.minCutoff,
         beta: Double = Config.Smoothing.beta,
         derivativeCutoff: Double = Config.Smoothing.derivativeCutoff) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// Feeds in a new raw value measured at `time` (seconds) and returns the smoothed value.
    mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let lastValue = previousValue, let lastTime = previousTime, time > lastTime else {
            // First sample (or a time glitch): nothing to smooth against yet.
            previousValue = value
            previousTime = time
            return value
        }
        let dt = time - lastTime

        // 1. Estimate how fast the value is changing (units per second), lightly smoothed.
        let rawSpeed = (value - lastValue) / dt
        let speedAlpha = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        let speed = speedAlpha * rawSpeed + (1 - speedAlpha) * previousSpeed

        // 2. Faster movement -> higher cutoff -> less smoothing -> less lag.
        let cutoff = minCutoff + beta * abs(speed)
        let valueAlpha = Self.alpha(cutoff: cutoff, dt: dt)

        // 3. Blend the new value with the previous smoothed value.
        let smoothed = valueAlpha * value + (1 - valueAlpha) * lastValue

        previousValue = smoothed
        previousSpeed = speed
        previousTime = time
        return smoothed
    }

    /// Forget history (e.g. after the face was lost for a while).
    mutating func reset() {
        previousValue = nil
        previousSpeed = 0
        previousTime = nil
    }

    /// Converts a cutoff frequency into a blend factor between 0 and 1 for this time step.
    /// alpha near 1 = "trust the new value" (no smoothing), near 0 = "keep the old value".
    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

/// Smooths all three head angles together.
struct HeadAnglesFilter {
    private var pitch = OneEuroFilter()
    private var yaw = OneEuroFilter()
    private var roll = OneEuroFilter()

    mutating func filter(_ angles: HeadAngles, at time: Double) -> HeadAngles {
        guard Config.Smoothing.enabled else { return angles }
        return HeadAngles(pitch: pitch.filter(angles.pitch, at: time),
                          yaw: yaw.filter(angles.yaw, at: time),
                          roll: roll.filter(angles.roll, at: time))
    }

    mutating func reset() {
        pitch.reset()
        yaw.reset()
        roll.reset()
    }
}

/// Smooths the expression values (mouth, eyebrows). Same filter, tuned for their scale.
struct ExpressionFilter {
    private var mouth = OneEuroFilter(beta: Config.Smoothing.expressionBeta)
    private var brow = OneEuroFilter(beta: Config.Smoothing.expressionBeta)

    mutating func filter(_ values: ExpressionValues, at time: Double) -> ExpressionValues {
        guard Config.Smoothing.enabled else { return values }
        return ExpressionValues(mouthOpen: mouth.filter(values.mouthOpen, at: time),
                                browHeight: brow.filter(values.browHeight, at: time))
    }

    mutating func reset() {
        mouth.reset()
        brow.reset()
    }
}
