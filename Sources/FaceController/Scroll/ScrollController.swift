import Foundation

// MARK: - Options and settings (saved between launches)

/// Scroll mode's two ways of scrolling (picked in the Scroll panel).
enum ScrollOption: String, Codable, CaseIterable, Identifiable {
    /// Tilt down/up = scroll the page down/up with real scroll-wheel events,
    /// faster the further you tilt. For reading pages, comments, search results.
    case smooth
    /// One quick head flick down = next Short (↓), up = previous Short (↑).
    /// Uses Snake's tap logic (flicks, re-arm, extra-turn guard).
    case shorts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: return "Smooth scroll"
        case .shorts: return "Shorts"
        }
    }
}

/// Scroll mode settings. Saved in UserDefaults, read tolerantly (like the Snake
/// settings). The Shorts flick sliders are a separate SnakeSettings, saved under
/// their own key (see SnakeSettings.loadShorts()).
struct ScrollSettings: Codable, Equatable {
    var option = Config.Scroll.defaultOption
    /// No scrolling within this many degrees of tilt (so small nods don't scroll).
    var deadzoneDegrees = Config.Scroll.defaultDeadzoneDegrees
    /// Speed multiplier (the Speed slider).
    var speed = Config.Scroll.defaultSpeed
    /// Flip the scroll direction (if a page scrolls the wrong way for you).
    var reverse = false
    /// Open your mouth = tap Space (YouTube play / pause).
    var mouthPlayPauseEnabled = Config.Scroll.defaultMouthPlayPause

    enum CodingKeys: String, CodingKey {
        case option, deadzoneDegrees, speed, reverse, mouthPlayPauseEnabled
    }

    /// What each gesture does in Scroll mode. (Smooth scrolling itself isn't a
    /// key: the engine sends it through ScrollController.)
    var bindings: [GestureID: OutputBinding] {
        var result: [GestureID: OutputBinding] = [:]
        if option == .shorts {
            result[.tiltDown] = Config.Scroll.nextShort
            result[.tiltUp] = Config.Scroll.previousShort
        }
        if mouthPlayPauseEnabled {
            result[.mouthOpen] = Config.Scroll.playPause
        }
        return result
    }

    func clamped() -> ScrollSettings {
        var copy = self
        copy.deadzoneDegrees = min(max(deadzoneDegrees, Config.Scroll.deadzoneRange.lowerBound),
                                   Config.Scroll.deadzoneRange.upperBound)
        copy.speed = min(max(speed, Config.Scroll.speedRange.lowerBound), Config.Scroll.speedRange.upperBound)
        return copy
    }

    // MARK: Saving

    private static let storageKey = "scrollSettings.v1"

    static func load() -> ScrollSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(ScrollSettings.self, from: data) else {
            return ScrollSettings()
        }
        return saved.clamped()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

extension ScrollSettings {
    /// Reads saved values, filling in defaults for anything missing or unknown.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScrollSettings()
        option = (try? container.decodeIfPresent(ScrollOption.self, forKey: .option)) ?? defaults.option
        deadzoneDegrees = try container.decodeIfPresent(Double.self, forKey: .deadzoneDegrees)
            ?? defaults.deadzoneDegrees
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? defaults.speed
        reverse = try container.decodeIfPresent(Bool.self, forKey: .reverse) ?? defaults.reverse
        mouthPlayPauseEnabled = try container.decodeIfPresent(Bool.self, forKey: .mouthPlayPauseEnabled)
            ?? defaults.mouthPlayPauseEnabled
    }
}

// MARK: - The scrolling math (pure, so it can be unit tested)

/// Head tilt → scroll speed, and smooth speeding up / slowing down.
///
///   tilt ──▶ deadzone ──▶ response curve ──▶ target speed ──▶ eased speed ──▶ pixels
///
/// - DEADZONE: small nods near the center don't scroll.
/// - CURVE: just past the deadzone it scrolls slowly (for reading); further out
///   it speeds up, reaching full speed at `Config.Scroll.fullSpeedDegrees`.
/// - EASING: the speed glides toward the target instead of jumping, so scrolling
///   starts gently and never jerks between camera frames. It slows down faster
///   than it speeds up, so it stops promptly when you look back to center.
///
/// Sign: + = scroll DOWN the page (toward later content), − = up.
struct ScrollMotion {
    /// Current (eased) speed, points per second.
    private(set) var speed: Double = 0
    /// Sub-point movement carried to the next step, so slow scrolling still adds up.
    private var remainder: Double = 0

    /// How fast the page should scroll for this head tilt (`up` = degrees tilted up).
    /// Tilt UP scrolls UP (negative), tilt DOWN scrolls DOWN (positive).
    static func targetSpeed(up: Double, settings: ScrollSettings) -> Double {
        let magnitude = abs(up)
        guard magnitude > settings.deadzoneDegrees else { return 0 }
        let span = max(Config.Scroll.fullSpeedDegrees - settings.deadzoneDegrees, 0.5)
        let t = min(1, (magnitude - settings.deadzoneDegrees) / span)
        let speed = Config.Scroll.maxSpeed * pow(t, Config.Scroll.curveExponent) * settings.speed
        let signed = up > 0 ? -speed : speed
        return settings.reverse ? -signed : signed
    }

    /// Moves the speed toward `target` over `dt` seconds and returns the whole points
    /// to scroll now (+ = down).
    mutating func step(toward target: Double, dt: Double) -> Int {
        let speedingUp = target * speed >= 0 && abs(target) > abs(speed)
        let easeTime = speedingUp ? Config.Scroll.speedUpTime : Config.Scroll.slowDownTime
        let blend = easeTime > 0 ? min(1, max(0, dt) / easeTime) : 1
        speed += (target - speed) * blend
        if target == 0 && abs(speed) < Config.Scroll.stopBelowSpeed {
            speed = 0
        }
        if speed == 0 {
            remainder = 0
            return 0
        }
        remainder += speed * max(0, dt)
        let whole = remainder.rounded(.towardZero)
        remainder -= whole
        return Int(whole)
    }

    /// Stop dead (safety: face lost, control off, mode change).
    mutating func reset() {
        speed = 0
        remainder = 0
    }
}

/// What smooth scrolling is doing (for the debug window).
struct ScrollState: Equatable {
    var option: ScrollOption = Config.Scroll.defaultOption
    var active = false
    /// Target speed, points per second (+ = down the page).
    var speed: Double = 0
    var inDeadzone = true
}

// MARK: - Sending the scroll events

/// Smooth scrolling output. Like AimController: the tracking loop only sets the
/// target speed; a 120 Hz timer on its own queue eases toward it and sends small
/// real scroll-wheel events, so the page glides instead of stepping 30 times a second.
final class ScrollController {
    private let input: VirtualInput
    private let queue = DispatchQueue(label: "FaceController.scroll", qos: .userInteractive)

    // Shared between the tracking queue (writes) and the scroll queue (reads): use `lock`.
    private let lock = NSLock()
    private var target = 0.0
    private var lastTargetTime = 0.0
    private var stopRequested = false

    // Only touched on `queue`.
    private var timer: DispatchSourceTimer?
    private var motion = ScrollMotion()
    private var lastTick: Double?

    init(input: VirtualInput) {
        self.input = input
    }

    /// Starts or stops the 120 Hz scroll timer (only runs in smooth scrolling).
    func setActive(_ active: Bool) {
        stopMoving()
        queue.async {
            if active {
                guard self.timer == nil else { return }
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(),
                               repeating: 1.0 / Config.Scroll.outputRate,
                               leeway: .microseconds(500))
                timer.setEventHandler { [weak self] in self?.tick() }
                timer.resume()
                self.timer = timer
            } else {
                self.timer?.cancel()
                self.timer = nil
            }
            self.motion.reset()
            self.lastTick = nil
        }
    }

    /// Stops scrolling IMMEDIATELY, without easing (face lost, control off...).
    func stopMoving() {
        lock.lock()
        target = 0
        stopRequested = true
        lock.unlock()
    }

    /// Called by the tracking loop every frame with how far the head is tilted up.
    func update(up: Double, settings: ScrollSettings, at time: Double) -> ScrollState {
        let speed = ScrollMotion.targetSpeed(up: up, settings: settings)
        lock.lock()
        target = speed
        lastTargetTime = time
        lock.unlock()
        return ScrollState(option: settings.option,
                           active: true,
                           speed: speed,
                           inDeadzone: abs(up) <= settings.deadzoneDegrees)
    }

    private func tick() {
        let now = HostClock.now()
        lock.lock()
        var want = target
        let stale = now - lastTargetTime > Config.Scroll.staleAfter
        let stop = stopRequested
        stopRequested = false
        lock.unlock()

        // Safety: a stop request, or no fresh head data (camera stalled, face lost).
        if stop || stale {
            motion.reset()
            want = 0
        }
        let dt = min(max(now - (lastTick ?? now), 0), 0.05)
        lastTick = now

        let points = motion.step(toward: want, dt: dt)
        if points != 0 {
            input.scroll(pointsDown: points)
        }
    }
}
