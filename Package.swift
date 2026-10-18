// swift-tools-version:5.9
// ^ This first line is required: it tells Swift Package Manager (SwiftPM) which
//   manifest format this file uses. 5.9 works with Xcode 15 and newer.

import PackageDescription

// Face Controller is a single executable target. Build and run it with:
//     swift run
// SwiftPM compiles every .swift file under Sources/FaceController into one program.
// Apple frameworks (AVFoundation, Vision, AppKit, Carbon, ...) are linked
// automatically because the source files `import` them. No third-party
// dependencies are used.
let package = Package(
    name: "FaceController",
    platforms: [
        .macOS(.v13)  // macOS 13 Ventura or newer.
    ],
    targets: [
        .executableTarget(
            name: "FaceController",
            path: "Sources/FaceController"
        )
    ]
)
