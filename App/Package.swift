// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CameramanApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../EngineKit")
    ],
    targets: [
        .executableTarget(
            name: "Cameraman",
            dependencies: ["EngineKit"],
            path: "Sources/Cameraman"
        ),
        .testTarget(
            name: "CameramanTests",
            dependencies: ["Cameraman"],
            path: "Tests/CameramanTests"
        ),
    ]
)
