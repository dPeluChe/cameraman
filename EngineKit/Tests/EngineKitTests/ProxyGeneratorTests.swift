//
//  ProxyGeneratorTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class ProxyGeneratorTests: XCTestCase {

    var proxyGenerator: ProxyGenerator!
    var tempDirectory: String!

    override func setUp() async throws {
        try await super.setUp()

        proxyGenerator = ProxyGenerator()

        // Create temporary directory for test files
        let tempDir = NSTemporaryDirectory()
        let uniqueDir = "ProxyGeneratorTests_\(UUID().uuidString)"
        tempDirectory = (tempDir as NSString).appendingPathComponent(uniqueDir)

        try FileManager.default.createDirectory(
            atPath: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        if FileManager.default.fileExists(atPath: tempDirectory) {
            try FileManager.default.removeItem(atPath: tempDirectory)
        }

        proxyGenerator = nil
        tempDirectory = nil

        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testConfigurationDefault() {
        let config = ProxyGenerator.Configuration.default
        XCTAssertEqual(config.width, 1280)
        XCTAssertEqual(config.height, 720)
        XCTAssertEqual(config.codec, .h264)
        XCTAssertEqual(config.outputFormat, .mov)
        XCTAssertEqual(config.targetBitrate, 2)
        XCTAssertTrue(config.preserveAspectRatio)
        XCTAssertEqual(config.frameRate, 30.0)
    }

    func testConfigurationHD1080() {
        let config = ProxyGenerator.Configuration.hd1080
        XCTAssertEqual(config.width, 1920)
        XCTAssertEqual(config.height, 1080)
        XCTAssertEqual(config.targetBitrate, 5)
        XCTAssertEqual(config.frameRate, 30.0)
    }

    func testConfigurationSD480() {
        let config = ProxyGenerator.Configuration.sd480
        XCTAssertEqual(config.width, 854)
        XCTAssertEqual(config.height, 480)
        XCTAssertEqual(config.targetBitrate, 1)
        XCTAssertEqual(config.frameRate, 24.0)
    }

    func testConfigurationCustom() {
        let config = ProxyGenerator.Configuration(
            width: 640,
            height: 480,
            codec: .hevc,
            outputFormat: .mp4,
            targetBitrate: 3,
            preserveAspectRatio: false,
            frameRate: 25.0
        )

        XCTAssertEqual(config.width, 640)
        XCTAssertEqual(config.height, 480)
        XCTAssertEqual(config.codec, .hevc)
        XCTAssertEqual(config.outputFormat, .mp4)
        XCTAssertEqual(config.targetBitrate, 3)
        XCTAssertFalse(config.preserveAspectRatio)
        XCTAssertEqual(config.frameRate, 25.0)
    }

    // MARK: - ProxyResult Tests

    func testProxyResultInitialization() {
        let result = ProxyGenerator.ProxyResult(
            proxyPath: "/tmp/proxy.mov",
            sourcePath: "/tmp/source.mov",
            duration: 10.0,
            sizeBytes: 1000,
            originalSizeBytes: 10000
        )

        XCTAssertEqual(result.proxyPath, "/tmp/proxy.mov")
        XCTAssertEqual(result.sourcePath, "/tmp/source.mov")
        XCTAssertEqual(result.duration, 10.0)
        XCTAssertEqual(result.sizeBytes, 1000)
        XCTAssertEqual(result.originalSizeBytes, 10000)
        XCTAssertEqual(result.compressionRatio, 10.0)
    }

    func testProxyResultCompressionRatio() {
        let result1 = ProxyGenerator.ProxyResult(
            proxyPath: "/tmp/proxy.mov",
            sourcePath: "/tmp/source.mov",
            duration: 10.0,
            sizeBytes: 1000,
            originalSizeBytes: 10000
        )
        XCTAssertEqual(result1.compressionRatio, 10.0)

        let result2 = ProxyGenerator.ProxyResult(
            proxyPath: "/tmp/proxy.mov",
            sourcePath: "/tmp/source.mov",
            duration: 10.0,
            sizeBytes: 5000,
            originalSizeBytes: 10000
        )
        XCTAssertEqual(result2.compressionRatio, 2.0)

        let result3 = ProxyGenerator.ProxyResult(
            proxyPath: "/tmp/proxy.mov",
            sourcePath: "/tmp/source.mov",
            duration: 10.0,
            sizeBytes: 0,
            originalSizeBytes: 0
        )
        XCTAssertEqual(result3.compressionRatio, 1.0)
    }

    // MARK: - ProxyError Tests

    func testProxyErrorDescriptions() {
        XCTAssertEqual(
            ProxyGenerator.ProxyError.sourceFileNotFound("/tmp/test.mov").localizedDescription,
            "Source file not found: /tmp/test.mov"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.sourceFileCorrupted("/tmp/test.mov").localizedDescription,
            "Source file is corrupted or unreadable: /tmp/test.mov"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.failedToCreateAsset("test reason").localizedDescription,
            "Failed to create asset: test reason"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.failedToCreateReader("test reason").localizedDescription,
            "Failed to create asset reader: test reason"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.failedToCreateWriter("test reason").localizedDescription,
            "Failed to create asset writer: test reason"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.failedToStartWriting("test reason").localizedDescription,
            "Failed to start writing: test reason"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.failedToStartSession("test reason").localizedDescription,
            "Failed to start session: test reason"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.failedToAppendSample("test reason").localizedDescription,
            "Failed to append sample: test reason"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.failedToFinishWriting("test reason").localizedDescription,
            "Failed to finish writing: test reason"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.insufficientDiskSpace(required: 1000, available: 500).localizedDescription,
            "Insufficient disk space: required 1000 bytes, available 500 bytes"
        )

        XCTAssertEqual(
            ProxyGenerator.ProxyError.cancelled.localizedDescription,
            "Proxy generation was cancelled"
        )
    }

    func testProxyErrorEquality() {
        let error1 = ProxyGenerator.ProxyError.sourceFileNotFound("/tmp/test.mov")
        let error2 = ProxyGenerator.ProxyError.sourceFileNotFound("/tmp/test.mov")
        let error3 = ProxyGenerator.ProxyError.sourceFileNotFound("/tmp/other.mov")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Helper Methods Tests

    func testGetProxyPathWithExistingProxy() async {
        // Create proxies directory and proxy file
        let proxiesDir = (tempDirectory as NSString).appendingPathComponent("proxies")
        try? FileManager.default.createDirectory(atPath: proxiesDir, withIntermediateDirectories: true)

        let proxyPath = (proxiesDir as NSString).appendingPathComponent("test_proxy.mov")
        FileManager.default.createFile(atPath: proxyPath, contents: Data())

        let sourcePath = "test.mov"
        let result = await proxyGenerator.getProxyPath(for: sourcePath, projectDirectory: tempDirectory)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, proxyPath)
    }

    func testGetProxyPathWithoutProxy() async {
        let sourcePath = "test.mov"
        let result = await proxyGenerator.getProxyPath(for: sourcePath, projectDirectory: tempDirectory)

        XCTAssertNil(result)
    }

    func testGetProxyPathWithoutProjectDirectory() async {
        let sourcePath = "test.mov"
        let result = await proxyGenerator.getProxyPath(for: sourcePath, projectDirectory: "")

        XCTAssertNil(result)
    }

    // MARK: - Integration Tests (with Mock Project)

    func testGenerateProjectProxiesWithoutSourceFiles() async {
        let project = createMockProject()

        do {
            _ = try await proxyGenerator.generateProjectProxies(
                for: project,
                projectDirectory: tempDirectory
            )
            XCTFail("Should have thrown ProxyError.sourceFileNotFound")
        } catch ProxyGenerator.ProxyError.sourceFileNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testGenerateProjectProxiesCreatesProxiesDirectory() async {
        let project = createMockProject()

        // Create source file
        let sourceDir = (tempDirectory as NSString).appendingPathComponent("sources")
        try? FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourcePath = (sourceDir as NSString).appendingPathComponent("screen.mov")
        FileManager.default.createFile(atPath: sourcePath, contents: Data([0, 1, 2, 3]))

        // Note: This will fail with a corrupted file error because the source file is not a valid video
        // We're just testing that the proxies directory creation logic works
        do {
            _ = try await proxyGenerator.generateProjectProxies(
                for: project,
                projectDirectory: tempDirectory
            )
        } catch {
            // Expected to fail due to invalid video file
        }

        // Verify proxies directory was created
        let proxiesDir = (tempDirectory as NSString).appendingPathComponent("proxies")
        XCTAssertTrue(FileManager.default.fileExists(atPath: proxiesDir))
    }

    // MARK: - Performance Tests

    func testPerformanceConfigurationCreation() {
        measure {
            _ = ProxyGenerator.Configuration.default
        }
    }

    func testPerformanceProxyResultCreation() {
        measure {
            _ = ProxyGenerator.ProxyResult(
                proxyPath: "/tmp/proxy.mov",
                sourcePath: "/tmp/source.mov",
                duration: 10.0,
                sizeBytes: 1000,
                originalSizeBytes: 10000
            )
        }
    }

    // MARK: - Helper Methods

    private func createMockProject() -> Project {
        let screenTrack = Project.Sources.MediaTrack(
            path: "sources/screen.mov",
            fps: 60.0,
            size: Project.Sources.Size(w: 1920, h: 1080),
            syncOffsetMs: 0,
            sha256: "abc123",
            sizeBytes: 1024000
        )

        let cameraTrack = Project.Sources.MediaTrack(
            path: "sources/camera.mov",
            fps: 30.0,
            size: Project.Sources.Size(w: 1280, h: 720),
            syncOffsetMs: 0,
            sha256: "def456",
            sizeBytes: 512000
        )

        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0,
                sourceOut: 5,
                timelineIn: 0,
                speed: 1.0
            )
        ]

        let timeline = Project.Timeline(duration: 5, segments: segments)

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "color", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "fullscreen", camera: nil)
        )

        let sources = Project.Sources(
            syncReference: "screen",
            screen: screenTrack,
            camera: cameraTrack,
            audio: nil,
            telemetry: nil
        )

        return Project(
            schemaVersion: 1,
            projectId: UUID(),
            name: "Test Project",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: sources,
            timeline: timeline,
            canvas: canvas,
            overlays: [],
            captions: nil
        )
    }
}
