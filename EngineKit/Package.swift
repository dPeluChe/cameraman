// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EngineKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "EngineKit",
            targets: ["EngineKit"]),
    ],
    dependencies: [
        // On-device transcription (CoreML / Apple Neural Engine). Used by
        // TranscriptionEngine via WhisperKitTranscriber, gated to Apple Silicon
        // at runtime. Pin/adjust the version to whatever your toolchain resolves.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "EngineKit",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/EngineKit"),
        .testTarget(
            name: "EngineKitTests",
            dependencies: ["EngineKit"],
            path: "Tests/EngineKitTests"),
    ]
)
