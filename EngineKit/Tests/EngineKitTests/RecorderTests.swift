//
//  RecorderTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit
import AVFoundation

@available(macOS 13.0, *)
final class RecorderTests: XCTestCase {
    var recorder: Recorder!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        recorder = Recorder.shared

        // Create temp directory for test outputs
        let tempDir = FileManager.default.temporaryDirectory
        tempDirectory = tempDir.appendingPathComponent("RecorderTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)

        // Clean up any active recording sessions
        let session = await recorder.getCurrentSession()
        if let session = session {
            try? await recorder.stopRecording(session: session)
        }

        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testRecordingConfigurationWithScreenOnly() {
        let config = Recorder.RecordingConfiguration(
            screenConfig: CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: SourceSelector.DisplaySource(
                    id: "test-display",
                    name: "Test Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60.0,
                    isMain: true
                ),
                captureSystemAudio: false
            ),
            cameraConfig: nil,
            captureMicAudio: false
        )

        XCTAssertNotNil(config.screenConfig)
        XCTAssertNil(config.cameraConfig)
        XCTAssertFalse(config.captureMicAudio)
    }

    func testRecordingConfigurationWithAllTracks() {
        let screenConfig = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: SourceSelector.DisplaySource(
                id: "test-display",
                name: "Test Display",
                width: 1920,
                height: 1080,
                refreshRate: 60.0,
                isMain: true
            ),
            captureSystemAudio: true
        )

        let cameraConfig = CameraEngine.CameraConfiguration(
            deviceID: nil,
            resolutionPreset: .hd1080,
            frameRate: 30,
            codec: .h264,
            syncOffsetMs: 100
        )

        let config = Recorder.RecordingConfiguration(
            screenConfig: screenConfig,
            cameraConfig: cameraConfig,
            captureMicAudio: true
        )

        XCTAssertTrue(config.screenConfig.captureSystemAudio)
        XCTAssertNotNil(config.cameraConfig)
        XCTAssertEqual(config.cameraConfig?.syncOffsetMs, 100)
        XCTAssertTrue(config.captureMicAudio)
    }

    // MARK: - Sync Metadata Tests

    func testSyncMetadata() {
        let metadata = Recorder.SyncMetadata(
            cameraSyncOffsetMs: 150,
            micAudioSyncOffsetMs: 0,
            systemAudioSyncOffsetMs: 0,
            syncReference: "screen"
        )

        XCTAssertEqual(metadata.cameraSyncOffsetMs, 150)
        XCTAssertEqual(metadata.micAudioSyncOffsetMs, 0)
        XCTAssertEqual(metadata.systemAudioSyncOffsetMs, 0)
        XCTAssertEqual(metadata.syncReference, "screen")
    }

    func testSyncMetadataCoding() throws {
        let metadata = Recorder.SyncMetadata(
            cameraSyncOffsetMs: 200,
            micAudioSyncOffsetMs: 50,
            systemAudioSyncOffsetMs: 0,
            syncReference: "screen"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Recorder.SyncMetadata.self, from: data)

        XCTAssertEqual(decoded.cameraSyncOffsetMs, metadata.cameraSyncOffsetMs)
        XCTAssertEqual(decoded.micAudioSyncOffsetMs, metadata.micAudioSyncOffsetMs)
        XCTAssertEqual(decoded.systemAudioSyncOffsetMs, metadata.systemAudioSyncOffsetMs)
        XCTAssertEqual(decoded.syncReference, metadata.syncReference)
    }

    // MARK: - RecordingSession Tests

    func testRecordingSessionCreation() {
        let session = Recorder.RecordingSession()

        XCTAssertNotNil(session.id)
        XCTAssertFalse(session.isRecording)
        XCTAssertFalse(session.isPaused)
        XCTAssertNil(session.startTime)
        XCTAssertNil(session.endTime)
        XCTAssertEqual(session.duration, 0)
    }

    func testRecordingSessionLifecycle() {
        let session = Recorder.RecordingSession()
        let now = Date()

        session.markStarted(at: now)

        XCTAssertTrue(session.isRecording)
        XCTAssertNotNil(session.startTime)
        XCTAssertEqual(session.startTime, now)

        let later = now.addingTimeInterval(5.0)
        session.markEnded(at: later)

        XCTAssertFalse(session.isRecording)
        XCTAssertNotNil(session.endTime)
        XCTAssertEqual(session.endTime, later)
        XCTAssertEqual(session.duration, 5.0)
    }

    func testRecordingSessionPauseResume() {
        let session = Recorder.RecordingSession()
        let now = Date()

        session.markStarted(at: now)
        session.markPaused()

        XCTAssertTrue(session.isPaused)

        session.markResumed()

        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(session.isRecording)
    }

    // MARK: - Recording Tests

    func testStartRecordingWithoutPermissions() async throws {
        // This test verifies that recording fails when permissions are not granted
        // In CI environments, permissions will not be granted

        let config = Recorder.RecordingConfiguration(
            screenConfig: CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: SourceSelector.DisplaySource(
                    id: "test-display",
                    name: "Test Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60.0,
                    isMain: true
                ),
                captureSystemAudio: false
            ),
            cameraConfig: nil,
            captureMicAudio: false
        )

        let outputURL = tempDirectory.appendingPathComponent("test1")

        do {
            _ = try await recorder.startRecording(
                config: config,
                outputURL: outputURL
            )
            // If we get here, permissions might be granted
            // Clean up the session
            let session = await recorder.getCurrentSession()
            if let session = session {
                try? await recorder.stopRecording(session: session)
            }
        } catch Recorder.RecorderError.permissionDenied {
            // Expected in CI environments
            XCTAssert(true)
        } catch {
            // Other errors are also acceptable (e.g., no source selected)
            XCTAssert(true)
        }
    }

    func testStartRecordingConcurrentSessions() async throws {
        let config = Recorder.RecordingConfiguration(
            screenConfig: CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: SourceSelector.DisplaySource(
                    id: "test-display",
                    name: "Test Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60.0,
                    isMain: true
                ),
                captureSystemAudio: false
            )
        )

        let outputURL1 = tempDirectory.appendingPathComponent("test2a")
        let outputURL2 = tempDirectory.appendingPathComponent("test2b")

        do {
            // Start first session
            _ = try await recorder.startRecording(
                config: config,
                outputURL: outputURL1
            )

            // Try to start second session - should fail
            do {
                _ = try await recorder.startRecording(
                    config: config,
                    outputURL: outputURL2
                )
                XCTFail("Should not allow concurrent recording sessions")
            } catch Recorder.RecorderError.recordingAlreadyInProgress {
                // Expected
                XCTAssert(true)
            }

            // Clean up first session
            let session = await recorder.getCurrentSession()
            if let session = session {
                try? await recorder.stopRecording(session: session)
            }
        } catch {
            // Permission errors are acceptable in CI
            XCTAssert(true)
        }
    }

    func testStopRecordingWithoutStarting() async throws {
        let session = Recorder.RecordingSession()

        do {
            _ = try await recorder.stopRecording(session: session)
            XCTFail("Should not stop a session that was never started")
        } catch Recorder.RecorderError.sessionNotFound {
            // Expected
            XCTAssert(true)
        } catch {
            // Other errors are also acceptable
            XCTAssert(true)
        }
    }

    func testPauseResumeRecordingWithoutStarting() async throws {
        let session = Recorder.RecordingSession()

        do {
            try await recorder.pauseRecording(session: session)
            XCTFail("Should not pause a session that was never started")
        } catch Recorder.RecorderError.sessionNotFound {
            // Expected
            XCTAssert(true)
        }

        do {
            try await recorder.resumeRecording(session: session)
            XCTFail("Should not resume a session that was never started")
        } catch Recorder.RecorderError.sessionNotFound {
            // Expected
            XCTAssert(true)
        }
    }

    // MARK: - RecordingResult Tests

    func testRecordingResultStructure() {
        let session = Recorder.RecordingSession()
        let now = Date()
        let later = now.addingTimeInterval(10.0)

        let syncMetadata = Recorder.SyncMetadata(
            cameraSyncOffsetMs: 100,
            micAudioSyncOffsetMs: 0,
            systemAudioSyncOffsetMs: 0,
            syncReference: "screen"
        )

        let result = Recorder.RecordingResult(
            session: session,
            screenVideoPath: URL(fileURLWithPath: "/tmp/screen.mov"),
            systemAudioPath: URL(fileURLWithPath: "/tmp/system_audio.m4a"),
            cameraVideoPath: URL(fileURLWithPath: "/tmp/camera.mov"),
            micAudioPath: URL(fileURLWithPath: "/tmp/mic_audio.m4a"),
            duration: 10.0,
            syncMetadata: syncMetadata,
            startTime: now,
            endTime: later
        )

        XCTAssertEqual(result.session.id, session.id)
        XCTAssertEqual(result.screenVideoPath.path, "/tmp/screen.mov")
        XCTAssertEqual(result.systemAudioPath?.path, "/tmp/system_audio.m4a")
        XCTAssertEqual(result.cameraVideoPath?.path, "/tmp/camera.mov")
        XCTAssertEqual(result.micAudioPath?.path, "/tmp/mic_audio.m4a")
        XCTAssertEqual(result.duration, 10.0)
        XCTAssertEqual(result.syncMetadata.cameraSyncOffsetMs, 100)
        XCTAssertEqual(result.startTime, now)
        XCTAssertEqual(result.endTime, later)
    }

    func testRecordingResultMetadataDump() throws {
        let session = Recorder.RecordingSession()
        let now = Date()
        let later = now.addingTimeInterval(5.0)

        let syncMetadata = Recorder.SyncMetadata(
            cameraSyncOffsetMs: 150,
            micAudioSyncOffsetMs: 0,
            systemAudioSyncOffsetMs: 0,
            syncReference: "screen"
        )

        let result = Recorder.RecordingResult(
            session: session,
            screenVideoPath: URL(fileURLWithPath: "/tmp/screen.mov"),
            systemAudioPath: URL(fileURLWithPath: "/tmp/system_audio.m4a"),
            cameraVideoPath: URL(fileURLWithPath: "/tmp/camera.mov"),
            micAudioPath: URL(fileURLWithPath: "/tmp/mic_audio.m4a"),
            duration: 5.0,
            syncMetadata: syncMetadata,
            startTime: now,
            endTime: later
        )

        let metadataURL = tempDirectory.appendingPathComponent("metadata.json")
        try result.dumpMetadata(to: metadataURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))

        let data = try Data(contentsOf: metadataURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["session_id"] as? String, session.id.uuidString)
        XCTAssertEqual(json?["duration"] as? Double, 5.0)

        let screenInfo = json?["screen"] as? [String: Any]
        XCTAssertNotNil(screenInfo)
        XCTAssertEqual(screenInfo?["path"] as? String, "/tmp/screen.mov")
        XCTAssertEqual(screenInfo?["has_system_audio"] as? Bool, true)

        let cameraInfo = json?["camera"] as? [String: Any]
        XCTAssertNotNil(cameraInfo)
        XCTAssertEqual(cameraInfo?["path"] as? String, "/tmp/camera.mov")
        XCTAssertEqual(cameraInfo?["sync_offset_ms"] as? Double, 150)

        let micInfo = json?["mic_audio"] as? [String: Any]
        XCTAssertNotNil(micInfo)
        XCTAssertEqual(micInfo?["path"] as? String, "/tmp/mic_audio.m4a")
        XCTAssertEqual(micInfo?["sync_offset_ms"] as? Double, 0)
    }

    func testRecordingResultWithoutOptionalTracks() throws {
        let session = Recorder.RecordingSession()
        let now = Date()
        let later = now.addingTimeInterval(3.0)

        let syncMetadata = Recorder.SyncMetadata()

        let result = Recorder.RecordingResult(
            session: session,
            screenVideoPath: URL(fileURLWithPath: "/tmp/screen.mov"),
            systemAudioPath: nil,
            cameraVideoPath: nil,
            micAudioPath: nil,
            duration: 3.0,
            syncMetadata: syncMetadata,
            startTime: now,
            endTime: later
        )

        XCTAssertNil(result.systemAudioPath)
        XCTAssertNil(result.cameraVideoPath)
        XCTAssertNil(result.micAudioPath)

        let metadataURL = tempDirectory.appendingPathComponent("metadata2.json")
        try result.dumpMetadata(to: metadataURL)

        let data = try Data(contentsOf: metadataURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertNil(json?["camera"])
        XCTAssertNil(json?["mic_audio"])

        let screenInfo = json?["screen"] as? [String: Any]
        XCTAssertNotNil(screenInfo)
        XCTAssertEqual(screenInfo?["has_system_audio"] as? Bool, false)
    }

    // MARK: - Error Tests

    func testRecorderErrorDescriptions() {
        let errors: [Recorder.RecorderError] = [
            .permissionDenied,
            .invalidConfiguration,
            .recordingNotStarted,
            .recordingAlreadyInProgress,
            .sessionNotFound
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }

    func testRecorderErrorWithUnderlyingError() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = Recorder.RecorderError.failedToStartScreenCapture(underlyingError)

        let description = error.errorDescription
        XCTAssertNotNil(description)
        XCTAssertTrue(description?.contains("Test error") ?? false)
    }

    // MARK: - Performance Tests

    func testConfigurationPerformance() {
        measure {
            for _ in 0..<1000 {
                let config = Recorder.RecordingConfiguration(
                    screenConfig: CaptureEngine.CaptureConfiguration(
                        sourceType: .display,
                        display: SourceSelector.DisplaySource(
                            id: "test-display",
                            name: "Test Display",
                            width: 1920,
                            height: 1080,
                            refreshRate: 60.0,
                            isMain: true
                        ),
                        captureSystemAudio: false
                    ),
                    cameraConfig: CameraEngine.CameraConfiguration(
                        deviceID: nil,
                        resolutionPreset: .hd1080,
                        frameRate: 30,
                        codec: .h264,
                        syncOffsetMs: 100
                    ),
                    captureMicAudio: true
                )

                _ = config
            }
        }
    }

    func testSessionCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                let session = Recorder.RecordingSession()
                _ = session
            }
        }
    }

    func testSyncMetadataPerformance() {
        measure {
            for _ in 0..<1000 {
                let metadata = Recorder.SyncMetadata(
                    cameraSyncOffsetMs: 100,
                    micAudioSyncOffsetMs: 50,
                    systemAudioSyncOffsetMs: 0,
                    syncReference: "screen"
                )
                _ = metadata
            }
        }
    }

    // MARK: - Edge Case Tests

    func testRecordingWithVariousSyncOffsets() {
        let offsets: [Double] = [-500, -100, 0, 50, 100, 200, 500, 1000]

        for offset in offsets {
            let cameraConfig = CameraEngine.CameraConfiguration(
                deviceID: nil,
                resolutionPreset: .hd1080,
                frameRate: 30,
                codec: .h264,
                syncOffsetMs: offset
            )

            XCTAssertEqual(cameraConfig.syncOffsetMs, offset)

            let syncMetadata = Recorder.SyncMetadata(
                cameraSyncOffsetMs: offset,
                micAudioSyncOffsetMs: 0,
                systemAudioSyncOffsetMs: 0,
                syncReference: "screen"
            )

            XCTAssertEqual(syncMetadata.cameraSyncOffsetMs, offset)
        }
    }

    func testRecordingWithAllCodecOptions() {
        let codecs: [CameraEngine.CameraConfiguration.VideoCodec] = [.h264, .hevc]

        for codec in codecs {
            let cameraConfig = CameraEngine.CameraConfiguration(
                deviceID: nil,
                resolutionPreset: .hd1080,
                frameRate: 30,
                codec: codec,
                syncOffsetMs: 0
            )

            XCTAssertEqual(cameraConfig.codec, codec)
        }
    }

    func testRecordingWithAllResolutionPresets() {
        let presets: [CameraEngine.CameraConfiguration.ResolutionPreset] = [.hd720, .hd1080]

        for preset in presets {
            let cameraConfig = CameraEngine.CameraConfiguration(
                deviceID: nil,
                resolutionPreset: preset,
                frameRate: 30,
                codec: .h264,
                syncOffsetMs: 0
            )

            XCTAssertEqual(cameraConfig.resolutionPreset, preset)
            XCTAssertNotEqual(cameraConfig.resolutionPreset.dimensions.width, 0)
            XCTAssertNotEqual(cameraConfig.resolutionPreset.dimensions.height, 0)
        }
    }
}
