import Foundation
@testable import FaceController

/// Simulated head movement, sampled like a 30 fps webcam, so the gesture logic can
/// be tested without a camera. Angles are degrees from the center, from the
/// player's point of view (+left / +up), like `PlayerHeadOffset`.
enum HeadMotion {
    static let frameRate = 30.0

    /// Frame times from 0 to `duration` seconds (inclusive), 1/30 s apart.
    static func frameTimes(duration: Double) -> [Double] {
        let count = Int((duration * frameRate).rounded())
        return (0...count).map { Double($0) / frameRate }
    }

    /// A quick, deliberate head turn starting at `start`: out to `amplitude` in `out`
    /// seconds, held for `hold`, then back to the center in `back` seconds, swinging
    /// `overshoot` degrees past the center the other way before settling (like a
    /// real head does after a big, fast move).
    static func turn(_ t: Double, start: Double, amplitude: Double,
                     out: Double = 0.12, hold: Double = 0.08, back: Double = 0.25,
                     overshoot: Double = 0) -> Double {
        var u = t - start
        if u < 0 { return 0 }
        if u < out { return amplitude * 0.5 * (1 - cos(Double.pi * u / out)) }
        u -= out
        if u < hold { return amplitude }
        u -= hold
        if u < back {
            return (amplitude + overshoot) / 2 * cos(Double.pi * u / back) + (amplitude - overshoot) / 2
        }
        u -= back
        guard overshoot != 0 else { return 0 }
        return -overshoot * exp(-u / 0.08) * cos(Double.pi * u / 0.25)
    }

    /// A slow, steady tilt from 0 to `amplitude` over `rise` seconds, then held.
    static func ramp(_ t: Double, start: Double, to amplitude: Double, rise: Double) -> Double {
        let u = t - start
        if u < 0 { return 0 }
        return amplitude * min(1, u / rise)
    }
}

/// What a SnakeController did over a whole simulated movement.
struct TapRun {
    struct Turn {
        let time: Double
        let gesture: GestureID
        let viaFlick: Bool
    }

    struct Blocked {
        let time: Double
        let gesture: GestureID
        let reason: String
        let isExtraTurn: Bool
    }

    var turns: [Turn] = []
    var blocked: [Blocked] = []

    var turnGestures: [GestureID] { turns.map { $0.gesture } }
    var verticalTurns: [GestureID] { turnGestures.filter { $0 == .tiltUp || $0 == .tiltDown } }

    /// Feeds a whole movement to a fresh SnakeController at 30 fps.
    /// `arm`: start ready (like after Recenter) instead of waiting for the center.
    static func run(settings: SnakeSettings, duration: Double, arm: Bool = true,
                    motion: (Double) -> PlayerHeadOffset) -> TapRun {
        var controller = SnakeController(settings: settings)
        if arm { controller.arm() }
        var run = TapRun()
        for time in HeadMotion.frameTimes(duration: duration) {
            let result = controller.update(offset: motion(time), at: time)
            for turn in result.turns {
                run.turns.append(Turn(time: time, gesture: turn.gesture, viaFlick: turn.viaFlick))
            }
            for blocked in result.blocked {
                run.blocked.append(Blocked(time: time, gesture: blocked.gesture,
                                           reason: blocked.reason, isExtraTurn: blocked.isExtraTurn))
            }
        }
        return run
    }
}
