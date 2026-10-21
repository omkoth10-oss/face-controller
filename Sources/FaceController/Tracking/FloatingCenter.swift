import Foundation

// MARK: - Settings (saved between launches)

/// Floating center on/off per mode, and how fast it follows. Saved in UserDefaults.
struct FloatingCenterSettings: Codable, Equatable {
    var keysEnabled = Config.FloatingCenter.defaultEnabled
    var aimEnabled = Config.FloatingCenter.defaultEnabled
    var snakeEnabled = Config.FloatingCenter.defaultEnabled
    var minecraftEnabled = Config.FloatingCenter.defaultEnabled
    var scrollEnabled = Config.FloatingCenter.defaultEnabled
    /// About how many seconds the center takes to catch up with your resting head.
    var followTime = Config.FloatingCenter.defaultFollowTime

    enum CodingKeys: String, CodingKey {
        case keysEnabled, aimEnabled, snakeEnabled, minecraftEnabled, scrollEnabled, followTime
    }

    func isEnabled(for mode: ControlMode) -> Bool {
        switch mode {
        case .keys: return keysEnabled
        case .aim: return aimEnabled
        case .snake: return snakeEnabled
        case .minecraft: return minecraftEnabled
        case .scroll: return scrollEnabled
        }
    }

    mutating func setEnabled(_ enabled: Bool, for mode: ControlMode) {
        switch mode {
        case .keys: keysEnabled = enabled
        case .aim: aimEnabled = enabled
        case .snake: snakeEnabled = enabled
        case .minecraft: minecraftEnabled = enabled
        case .scroll: scrollEnabled = enabled
        }
    }

    func clamped() -> FloatingCenterSettings {
        var copy = self
        let range = Config.FloatingCenter.followTimeRange
        copy.followTime = min(max(followTime, range.lowerBound), range.upperBound)
        return copy
    }

    // MARK: Saving

    private static let storageKey = "floatingCenter.v1"

    static func load() -> FloatingCenterSettings {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(FloatingCenterSettings.self, from: data) {
            return saved.clamped()
        }
        // First launch with this feature: keep your old Snake "auto-recenter" choice,
        // and save right away (the old value disappears once Snake settings are re-saved).
        var settings = FloatingCenterSettings()
        if let legacy = SnakeSettings.legacyDriftCorrection() {
            settings.snakeEnabled = legacy
        }
        settings.save()
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

extension FloatingCenterSettings {
    /// Reads saved values, filling in defaults for anything missing, so adding a
    /// setting later never wipes the ones you already saved.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FloatingCenterSettings()
        keysEnabled = try container.decodeIfPresent(Bool.self, forKey: .keysEnabled) ?? defaults.keysEnabled
        aimEnabled = try container.decodeIfPresent(Bool.self, forKey: .aimEnabled) ?? defaults.aimEnabled
        snakeEnabled = try container.decodeIfPresent(Bool.self, forKey: .snakeEnabled) ?? defaults.snakeEnabled
        minecraftEnabled = try container.decodeIfPresent(Bool.self, forKey: .minecraftEnabled)
            ?? defaults.minecraftEnabled
        scrollEnabled = try container.decodeIfPresent(Bool.self, forKey: .scrollEnabled) ?? defaults.scrollEnabled
        followTime = try container.decodeIfPresent(Double.self, forKey: .followTime) ?? defaults.followTime
    }
}

// MARK: - The floating center itself

/// What the floating center is doing (for the debug window).
struct FloatingCenterStatus {
    var enabled = false
    /// e.g. "following your head (resting)" or "paused: A held".
    var state = "—"
    var isFollowing = false
    /// How far the center has moved from your last calibration / recenter (degrees).
    var shiftDegrees: Double = 0
}

/// Decides, frame by frame, whether the center may follow your head, and moves it.
///
/// In plain language: when your head has been resting still near the center for a
/// moment, the center slowly slides to where your head actually is. So if you lean,
/// slouch or turn your chair a bit, "center" comes with you and nothing fires by
/// itself. It NEVER moves while something is happening (a key held, a turn about to
/// fire, the pointer moving), so it can't cancel what you're doing.
struct FloatingCenter {
    private var restingSince: Double?
    private var lastOffset: PlayerHeadOffset?
    private var lastTime: Double?
    /// Head speed (degrees per second, the faster of the two axes), lightly smoothed.
    private(set) var speed: Double = 0
    private(set) var state = "—"
    private(set) var isFollowing = false

    /// Call every frame (after the gestures ran).
    /// - neutral: the center, moved in place when following.
    /// - head: current head angles (camera view, smoothed).
    /// - offset: current head offset from the center (player view).
    /// - zone: how close to the center counts as "near center" (degrees).
    /// - busyReason: non-nil when a direction is firing/held or the pointer is moving.
    mutating func update(neutral: inout HeadAngles,
                         head: HeadAngles,
                         offset: PlayerHeadOffset,
                         zone: Double,
                         busyReason: String?,
                         followTime: Double,
                         at time: Double) {
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        if let last = lastOffset, dt > 0 {
            let instant = max(abs(offset.left - last.left), abs(offset.up - last.up)) / dt
            speed = 0.5 * speed + 0.5 * instant
        }
        lastOffset = offset
        lastTime = time
        isFollowing = false

        if let busy = busyReason {
            restingSince = nil
            state = "paused: \(busy)"
            return
        }
        guard abs(offset.left) < zone, abs(offset.up) < zone else {
            restingSince = nil
            state = String(format: "paused: head more than %.1f° from center", zone)
            return
        }
        guard speed < Config.FloatingCenter.stillSpeed else {
            restingSince = nil
            state = "waiting: head moving"
            return
        }
        let since = restingSince ?? time
        restingSince = since
        guard time - since >= Config.FloatingCenter.restDwell else {
            state = "waiting: head settling"
            return
        }

        // Slide a small step toward where the head is resting.
        let step = min(1, dt / max(followTime, 0.05))
        neutral.pitch += (head.pitch - neutral.pitch) * step
        neutral.yaw += (head.yaw - neutral.yaw) * step
        neutral.roll += (head.roll - neutral.roll) * step
        isFollowing = true
        state = "following your head (resting)"
    }

    /// Forget timing history (after recenter, calibration, mode switch, face lost).
    mutating func reset() {
        restingSince = nil
        lastOffset = nil
        lastTime = nil
        speed = 0
        isFollowing = false
        state = "—"
    }

    mutating func markOff(_ reason: String) {
        reset()
        state = reason
    }
}
