import Foundation

/// What a gesture wants to do with its key this frame.
enum GestureEvent {
    case press
    case release
}

/// A gesture's current state, for the debug window.
enum GesturePhase: Equatable {
    /// Won't fire until you return to neutral first (after calibration, after the
    /// face was lost, or after control was turned back on). Prevents surprise presses.
    case waitingForNeutral
    /// Armed and waiting for you to pass the press threshold.
    case ready
    /// Past the press threshold; waiting out the hold time. progress = 0...1.
    case holding(progress: Double)
    /// Key is held down.
    case active
}

/// Turns one number (e.g. "degrees tilted up") into key press / release events.
///
/// Two ideas keep it from misfiring:
///
/// 1. HYSTERESIS: two thresholds. Press at `pressThreshold` (e.g. 10°) but only
///    release below the lower `releaseThreshold` (e.g. 6°). Hovering around 10°
///    therefore can't make the key flicker on/off.
///
/// 2. HOLD TIME: the value must stay past the press threshold for `holdTime`
///    (e.g. 80 ms) before the key is pressed. A quick accidental twitch is ignored.
///    Releasing is immediate, so letting go always feels instant.
///
///        value
///          ^
///   press  |- - - - - -+=========+- - - -     <- must stay above for holdTime
///  release |- - - - - -|- - - - -|- -+- -     <- released when it drops below here
///          |    ready  | holding | active |ready
///          +----------------------------------> time
struct ThresholdGesture {
    let pressThreshold: Double
    let releaseThreshold: Double
    let holdTime: Double

    private enum State {
        case waitingForNeutral
        case ready
        case holding(since: Double)
        case active
    }

    private var state: State = .waitingForNeutral
    private var lastUpdateTime: Double = 0

    init(pressThreshold: Double, releaseThreshold: Double, holdTime: Double) {
        self.pressThreshold = pressThreshold
        // Guard against a typo in Config.swift: release must be below press.
        self.releaseThreshold = min(releaseThreshold, pressThreshold)
        self.holdTime = max(0, holdTime)
    }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var phase: GesturePhase {
        switch state {
        case .waitingForNeutral:
            return .waitingForNeutral
        case .ready:
            return .ready
        case .holding(let since):
            let progress = holdTime > 0 ? (lastUpdateTime - since) / holdTime : 1
            return .holding(progress: min(1, max(0, progress)))
        case .active:
            return .active
        }
    }

    /// Feed in the latest value. Returns `.press` or `.release` when the key should change.
    mutating func update(value: Double, at time: Double) -> GestureEvent? {
        lastUpdateTime = time
        switch state {
        case .waitingForNeutral:
            if value < releaseThreshold {
                state = .ready
            }
            return nil

        case .ready:
            guard value >= pressThreshold else { return nil }
            state = .holding(since: time)
            return finishHoldIfDone(now: time, since: time)

        case .holding(let since):
            guard value >= pressThreshold else {
                state = .ready  // Dropped back before the hold time finished: cancel.
                return nil
            }
            return finishHoldIfDone(now: time, since: since)

        case .active:
            if value < releaseThreshold {
                state = .ready
                return .release
            }
            return nil
        }
    }

    /// Cancels a hold that's in progress (used when a frame has no face).
    /// Does not touch an active key.
    mutating func cancelHold() {
        if case .holding = state {
            state = .ready
        }
    }

    /// Forget the current state. With `requireNeutral`, the gesture won't fire again
    /// until the value has dropped below the release threshold.
    /// The CALLER is responsible for releasing the key if it was held.
    mutating func reset(requireNeutral: Bool) {
        state = requireNeutral ? .waitingForNeutral : .ready
    }

    private mutating func finishHoldIfDone(now: Double, since: Double) -> GestureEvent? {
        guard now - since >= holdTime else { return nil }
        state = .active
        return .press
    }
}
