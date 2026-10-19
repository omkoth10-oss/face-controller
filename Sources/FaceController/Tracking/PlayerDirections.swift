import Foundation

/// How far your head is turned/tilted from neutral, from YOUR point of view, in degrees.
struct PlayerHeadOffset: Equatable {
    /// Positive = turned to YOUR left, negative = to your right.
    var left: Double
    /// Positive = tilted up (chin up), negative = down.
    var up: Double
}

/// Converts Vision's camera-based angles into the player's directions.
///
/// Why this is needed (the tricky part): Vision measures the face as it appears in
/// the camera image. The camera faces you, so its picture is like someone looking
/// at you: YOUR left is on the RIGHT side of the image. If the frames are mirrored
/// (like a selfie), it's the other way round. This is the ONE place where we sort
/// that out, so every gesture, the aiming and the direction pad agree.
enum PlayerDirections {
    static func offset(relative: HeadAngles, framesMirrored: Bool) -> PlayerHeadOffset {
        // Vertical: Vision's pitch goes NEGATIVE when you tilt your head up
        // (this is how Phase 1's "tilt up = Space" worked on the owner's Mac).
        var up = -relative.pitch

        // Horizontal: Vision's yaw is positive when the face turns toward the RIGHT
        // side of the image (the same rotation convention as its pitch and roll).
        // In normal (unmirrored) frames the image's right side is YOUR left.
        // In mirrored frames it's your right, so the sign flips.
        var left = framesMirrored ? -relative.yaw : relative.yaw

        // Manual overrides for cameras that still come out backwards.
        if Config.Directions.flipHorizontal { left = -left }
        if Config.Directions.flipVertical { up = -up }

        return PlayerHeadOffset(left: left, up: up)
    }
}
