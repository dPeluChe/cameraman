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
        // Dependencies will be added as needed:
        // .package(url: "https://github.com/ggerganov/whisper.cpp", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "EngineKit",
            dependencies: [],
            path: "Sources/EngineKit"),
        .testTarget(
            name: "EngineKitTests",
            dependencies: ["EngineKit"],
            path: "Tests/EngineKitTests"),
    ]
)
