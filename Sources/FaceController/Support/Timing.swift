import CoreMedia

/// One clock for the whole app.
///
/// We use the "host time" clock: a monotonic clock (it never jumps when the
/// wall-clock time changes). It's the same clock AVFoundation uses to timestamp
/// camera frames on the Mac, which lets us measure how old a frame is.
enum HostClock {
    /// Current time in seconds.
    static func now() -> Double {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }
}

/// Average of the last N values. Used for the timing numbers in the debug window
/// so they don't flicker every frame.
struct RollingAverage {
    private var values: [Double] = []
    private var nextIndex = 0
    private let capacity: Int

    init(capacity: Int = Config.UI.statsWindow) {
        self.capacity = max(1, capacity)
        values.reserveCapacity(self.capacity)
    }

    mutating func add(_ value: Double) {
        if values.count < capacity {
            values.append(value)
        } else {
            values[nextIndex] = value  // Overwrite the oldest value (ring buffer).
        }
        nextIndex = (nextIndex + 1) % capacity
    }

    /// nil until at least one value has been added.
    var average: Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    var maximum: Double? { values.max() }
}

/// Counts events per second (used for camera FPS).
struct RateCounter {
    private var windowStart: Double?
    private var count = 0
    private(set) var rate: Double = 0

    mutating func tick(at time: Double) {
        guard let start = windowStart else {
            windowStart = time
            count = 0
            return
        }
        count += 1
        let elapsed = time - start
        if elapsed >= 1.0 {
            rate = Double(count) / elapsed
            windowStart = time
            count = 0
        }
    }
}
