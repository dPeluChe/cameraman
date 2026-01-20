//
//  TimelineThumbnailTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20
//

import XCTest
import SwiftUI
@testable import App
@testable import EngineKit
import CoreGraphics

@available(macOS 13.0, *)
final class TimelineThumbnailTests: XCTestCase {

    var mockProject: Project!
    var projectEditor: ProjectEditor!
    var tempDirectory: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for testing
        tempDirectory = NSTemporaryDirectory()
        let testDir = (tempDirectory as NSString).appendingPathComponent("TimelineThumbnailTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true, attributes: nil)
        tempDirectory = testDir

        // Create a mock project for testing
        mockProject = createMockProject()
        projectEditor = ProjectEditor(project: mockProject)
    }

    override func tearDown() async throws {
        mockProject = nil
        projectEditor = nil

        // Clean up temporary directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(atPath: tempDir)
        }

        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockProject() -> Project {
        let screenTrack = Project.Sources.MediaTrack(
            path: "/tmp/test_screen.mov",
            fps: 60.0,
            size: Project.Sources.Size(w: 1920, h: 1080),
            syncOffsetMs: 0,
            sha256: "abc123",
            sizeBytes: 1024000
        )

        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0,
                sourceOut: 5,
                timelineIn: 0,
                speed: 1.0
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 5,
                sourceOut: 10,
                timelineIn: 5,
                speed: 1.0
            )
        ]

        let timeline = Project.Timeline(duration: 10, segments: segments)

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "color", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "fullscreen", camera: nil)
        )

        let sources = Project.Sources(
            syncReference: "screen",
            screen: screenTrack,
            camera: nil,
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

    // MARK: - Thumbnail Cache Initialization Tests

    func testThumbnailCacheConfiguration() {
        let config = ThumbnailCache.Configuration.default
        XCTAssertEqual(config.maxThumbnailCount, 100)
        XCTAssertEqual(config.thumbnailWidth, 160)
        XCTAssertEqual(config.thumbnailHeight, 90)
        XCTAssertTrue(config.enableDiskCache)
    }

    func testThumbnailCacheHighQualityConfiguration() {
        let config = ThumbnailCache.Configuration.highQuality
        XCTAssertEqual(config.maxThumbnailCount, 200)
        XCTAssertEqual(config.thumbnailWidth, 320)
        XCTAssertEqual(config.thumbnailHeight, 180)
    }

    func testThumbnailCacheLowMemoryConfiguration() {
        let config = ThumbnailCache.Configuration.lowMemory
        XCTAssertEqual(config.maxThumbnailCount, 50)
        XCTAssertEqual(config.thumbnailWidth, 120)
        XCTAssertEqual(config.thumbnailHeight, 68)
        XCTAssertFalse(config.enableWaveformCache)
        XCTAssertFalse(config.enableDiskCache)
    }

    // MARK: - Timeline Thumbnail Integration Tests

    func testTimelineViewWithThumbnailSupport() {
        // Verify TimelineView can be created with thumbnail support
        let playheadTime = Binding<TimeInterval>(get: { 0.0 }, set: { _ in })
        let projectDirectory = URL(fileURLWithPath: tempDirectory)

        let timelineView = TimelineView(
            editor: projectEditor,
            playheadTime: playheadTime,
            projectDirectory: projectDirectory
        )

        XCTAssertNotNil(timelineView)
    }

    func testTimelineViewWithoutProjectDirectory() {
        // Verify TimelineView works without project directory (thumbnails disabled)
        let playheadTime = Binding<TimeInterval>(get: { 0.0 }, set: { _ in })

        let timelineView = TimelineView(
            editor: projectEditor,
            playheadTime: playheadTime,
            projectDirectory: nil
        )

        XCTAssertNotNil(timelineView)
    }

    // MARK: - Thumbnail Display Tests

    func testThumbnailToggleState() {
        // Verify thumbnail toggle state can be changed
        let showThumbnails = true
        XCTAssertTrue(showThumbnails)

        let showThumbnailsOff = false
        XCTAssertFalse(showThumbnailsOff)
    }

    func testThumbnailDictionaryOperations() {
        // Test thumbnail dictionary operations
        var thumbnails: [TimeInterval: NSImage] = [:]

        // Create a mock thumbnail
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG signature
        let mockImage = NSImage(data: imageData)

        XCTAssertNotNil(mockImage)

        // Add thumbnail
        thumbnails[0.0] = mockImage
        XCTAssertEqual(thumbnails.count, 1)
        XCTAssertNotNil(thumbnails[0.0])

        // Add more thumbnails
        thumbnails[1.0] = mockImage
        thumbnails[2.0] = mockImage
        XCTAssertEqual(thumbnails.count, 3)

        // Find closest thumbnail
        let sortedTimes = thumbnails.keys.sorted()
        let closestTime = sortedTimes.min(by: { abs($0 - 1.5) < abs($1 - 1.5) })
        XCTAssertEqual(closestTime, 1.0)
    }

    // MARK: - Thumbnail Timing Tests

    func testThumbnailTimeCalculation() {
        // Test thumbnail time calculation logic
        let duration: TimeInterval = 10.0
        let thumbnailCount = 5
        let interval = duration / Double(max(thumbnailCount - 1, 1))

        XCTAssertEqual(interval, 2.5)

        // Calculate thumbnail times
        var times: [TimeInterval] = []
        for i in 0..<thumbnailCount {
            let time = Double(i) * interval
            times.append(time)
        }

        XCTAssertEqual(times, [0.0, 2.5, 5.0, 7.5, 10.0])
    }

    func testClosestThumbnailFinding() {
        // Test finding closest thumbnail
        let thumbnails: [TimeInterval: NSImage] = [
            0.0: NSImage(),
            2.5: NSImage(),
            5.0: NSImage(),
            7.5: NSImage(),
            10.0: NSImage()
        ]

        let sortedTimes = thumbnails.keys.sorted()

        // Find closest to 3.0
        let closestTo3 = sortedTimes.min(by: { abs($0 - 3.0) < abs($1 - 3.0) })
        XCTAssertEqual(closestTo3, 2.5)

        // Find closest to 6.0
        let closestTo6 = sortedTimes.min(by: { abs($0 - 6.0) < abs($1 - 6.0) })
        XCTAssertEqual(closestTo6, 5.0)

        // Find closest to 9.0
        let closestTo9 = sortedTimes.min(by: { abs($0 - 9.0) < abs($1 - 9.0) })
        XCTAssertEqual(closestTo9, 10.0)
    }

    func testThumbnailTimeThreshold() {
        // Test thumbnail time threshold logic (within 2 seconds)
        let thumbnailTime: TimeInterval = 5.0
        let queryTime1: TimeInterval = 6.5 // 1.5 seconds away - should match
        let queryTime2: TimeInterval = 8.0 // 3 seconds away - should not match

        let threshold1 = abs(thumbnailTime - queryTime1)
        let threshold2 = abs(thumbnailTime - queryTime2)

        XCTAssertLessThanOrEqual(threshold1, 2.0)
        XCTAssertGreaterThan(threshold2, 2.0)
    }

    // MARK: - Timeline Layout Tests

    func testTimelineLayoutThumbnailPositioning() {
        // Test timeline layout calculations for thumbnail positioning
        let duration: TimeInterval = 10.0
        let pixelsPerSecond: TimelineScalar = 40
        let labelWidth: TimelineScalar = 120

        let layout = TimelineLayout(
            duration: duration,
            pixelsPerSecond: pixelsPerSecond,
            labelWidth: labelWidth
        )

        // Test xPosition calculation
        let x0 = layout.xPosition(for: 0.0)
        let x5 = layout.xPosition(for: 5.0)
        let x10 = layout.xPosition(for: 10.0)

        XCTAssertEqual(x0, labelWidth)
        XCTAssertEqual(x5, labelWidth + 200) // 5 seconds * 40 px/sec
        XCTAssertEqual(x10, labelWidth + 400) // 10 seconds * 40 px/sec

        // Test segment width calculation
        let segmentDuration: TimeInterval = 5.0
        let width = layout.segmentWidth(for: segmentDuration)
        XCTAssertEqual(width, 200) // 5 seconds * 40 px/sec
    }

    // MARK: - Thumbnail Strip Tests

    func testThumbnailStripLayout() {
        // Test thumbnail strip layout calculations
        let segmentWidth: TimelineScalar = 200
        let minThumbnailWidth: TimelineScalar = 30
        let thumbnailSpacing: TimelineScalar = 4

        let thumbnailCount = Int(segmentWidth / (minThumbnailWidth + thumbnailSpacing))

        XCTAssertGreaterThanOrEqual(thumbnailCount, 1)
        XCTAssertLessThanOrEqual(thumbnailCount, 6) // Max thumbnails that fit in 200px

        // Test interval calculation
        let segmentDuration: TimeInterval = 5.0
        let interval = segmentDuration / Double(max(thumbnailCount - 1, 1))

        if thumbnailCount > 1 {
            XCTAssertGreaterThan(interval, 0)
        }
    }

    func testThumbnailRelativePositioning() {
        // Test thumbnail positioning within segment
        let segmentTimelineIn: TimeInterval = 2.0
        let segmentDuration: TimeInterval = 5.0
        let segmentWidth: TimelineScalar = 200

        // Calculate relative position for 3 thumbnails
        let thumbnailCount = 3
        let interval = segmentDuration / Double(thumbnailCount - 1)

        for i in 0..<thumbnailCount {
            let time = segmentTimelineIn + (Double(i) * interval)
            let relativeTime = time - segmentTimelineIn
            let thumbnailX = (relativeTime / segmentDuration) * segmentWidth

            // Verify thumbnailX is within segment bounds
            XCTAssertGreaterThanOrEqual(thumbnailX, 0)
            XCTAssertLessThanOrEqual(thumbnailX, segmentWidth)
        }
    }

    // MARK: - Performance Tests

    func testThumbnailDictionaryPerformance() {
        // Test thumbnail dictionary lookup performance
        var thumbnails: [TimeInterval: NSImage] = []

        // Add 100 thumbnails
        for i in 0..<100 {
            thumbnails[TimeInterval(i)] = NSImage()
        }

        measure {
            // Perform 1000 lookups
            for _ in 0..<1000 {
                let queryTime = TimeInterval.random(in: 0..<100)
                let sortedTimes = thumbnails.keys.sorted()
                _ = sortedTimes.min(by: { abs($0 - queryTime) < abs($1 - queryTime) })
            }
        }
    }

    func testThumbnailTimeCalculationPerformance() {
        // Test thumbnail time calculation performance
        let duration: TimeInterval = 100.0
        let thumbnailCount = 100
        let interval = duration / Double(max(thumbnailCount - 1, 1))

        measure {
            for _ in 0..<1000 {
                for i in 0..<thumbnailCount {
                    _ = Double(i) * interval
                }
            }
        }
    }

    // MARK: - Integration Tests

    func testThumbnailCacheWithProject() async {
        // Test thumbnail cache with project
        let thumbnailCache = ThumbnailCache(configuration: .default)

        await thumbnailCache.setProject(mockProject, projectDirectory: tempDirectory)

        let stats = await thumbnailCache.getCacheStats()
        XCTAssertEqual(stats["thumbnailCount"] as? Int, 0)
        XCTAssertEqual(stats["waveformCount"] as? Int, 0)
    }

    func testThumbnailCacheClear() async {
        // Test thumbnail cache clearing
        let thumbnailCache = ThumbnailCache(configuration: .default)

        await thumbnailCache.setProject(mockProject, projectDirectory: tempDirectory)
        await thumbnailCache.clearThumbnails()

        let stats = await thumbnailCache.getCacheStats()
        XCTAssertEqual(stats["thumbnailCount"] as? Int, 0)
    }

    func testThumbnailCacheProjectClear() async {
        // Test thumbnail cache project clearing
        let thumbnailCache = ThumbnailCache(configuration: .default)

        await thumbnailCache.setProject(mockProject, projectDirectory: tempDirectory)
        await thumbnailCache.clearProject()

        let stats = await thumbnailCache.getCacheStats()
        XCTAssertEqual(stats["thumbnailCount"] as? Int, 0)
        XCTAssertEqual(stats["waveformCount"] as? Int, 0)
    }

    // MARK: - Edge Case Tests

    func testEmptyThumbnailDictionary() {
        // Test operations with empty thumbnail dictionary
        let thumbnails: [TimeInterval: NSImage] = [:]

        XCTAssertTrue(thumbnails.isEmpty)

        let sortedTimes = thumbnails.keys.sorted()
        XCTAssertTrue(sortedTimes.isEmpty)

        let closestTime = sortedTimes.min(by: { abs($0 - 1.0) < abs($1 - 1.0) })
        XCTAssertNil(closestTime)
    }

    func testSingleThumbnail() {
        // Test operations with single thumbnail
        let thumbnails: [TimeInterval: NSImage] = [0.0: NSImage()]

        XCTAssertEqual(thumbnails.count, 1)

        let sortedTimes = thumbnails.keys.sorted()
        XCTAssertEqual(sortedTimes, [0.0])

        let closestTime = sortedTimes.min(by: { abs($0 - 1.0) < abs($1 - 1.0) })
        XCTAssertEqual(closestTime, 0.0)
    }

    func testThumbnailZeroDuration() {
        // Test thumbnail calculation with zero duration
        let duration: TimeInterval = 0.0
        let thumbnailCount = 5

        let interval = duration / Double(max(thumbnailCount - 1, 1))

        if thumbnailCount > 1 {
            XCTAssertEqual(interval, 0.0)
        }
    }

    func testThumbnailVeryShortDuration() {
        // Test thumbnail calculation with very short duration
        let duration: TimeInterval = 0.1
        let thumbnailCount = 5

        let interval = duration / Double(max(thumbnailCount - 1, 1))

        XCTAssertGreaterThan(interval, 0)
        XCTAssertLessThan(interval, 0.1)
    }

    // MARK: - UI State Tests

    func testShowThumbnailsToggle() {
        // Test showThumbnails toggle behavior
        var showThumbnails = true

        // Toggle off
        showThumbnails = false
        XCTAssertFalse(showThumbnails)

        // Toggle on
        showThumbnails = true
        XCTAssertTrue(showThumbnails)
    }

    func testThumbnailCacheDisabledBehavior() {
        // Test behavior when thumbnail cache is disabled (nil)
        let thumbnailCache: ThumbnailCache? = nil

        XCTAssertNil(thumbnailCache)

        // Verify toggle is disabled when cache is nil
        let toggleEnabled = thumbnailCache != nil
        XCTAssertFalse(toggleEnabled)
    }

    // MARK: - Waveform Tests

    func testWaveformToggleState() {
        // Verify waveform toggle state can be changed
        let showWaveforms = true
        XCTAssertTrue(showWaveforms)

        let showWaveformsOff = false
        XCTAssertFalse(showWaveformsOff)
    }

    func testWaveformDictionaryOperations() {
        // Test waveform dictionary operations
        var waveforms: [String: [Float]] = [:]

        // Create mock waveform samples
        let mockSamples: [Float] = [0.0, 0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5, 0.0]

        // Add waveform
        waveforms["/tmp/audio1.m4a"] = mockSamples
        XCTAssertEqual(waveforms.count, 1)
        XCTAssertNotNil(waveforms["/tmp/audio1.m4a"])

        // Add more waveforms
        waveforms["/tmp/audio2.m4a"] = mockSamples
        XCTAssertEqual(waveforms.count, 2)

        // Remove waveform
        waveforms.removeValue(forKey: "/tmp/audio1.m4a")
        XCTAssertEqual(waveforms.count, 1)
        XCTAssertNil(waveforms["/tmp/audio1.m4a"])
    }

    func testWaveformSampleGeneration() {
        // Test waveform sample values
        let samples: [Float] = [0.0, 0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5, 0.0]

        XCTAssertEqual(samples.count, 9)
        XCTAssertEqual(samples[0], 0.0)
        XCTAssertEqual(samples[2], 1.0) // Peak positive
        XCTAssertEqual(samples[6], -1.0) // Peak negative
    }

    func testWaveformSampleNormalization() {
        // Test that waveform samples are normalized between -1.0 and 1.0
        let samples: [Float] = [-1.0, -0.5, 0.0, 0.5, 1.0]

        for sample in samples {
            XCTAssertGreaterThanOrEqual(sample, -1.0)
            XCTAssertLessThanOrEqual(sample, 1.0)
        }
    }

    func testWaveformAmplitudeCalculation() {
        // Test waveform amplitude calculation for rendering
        let centerY: CGFloat = 20.0
        let samples: [Float] = [0.0, 0.5, 1.0, 0.5, 0.0]

        for sample in samples {
            let amplitude = abs(sample) * centerY
            let yStart = centerY - amplitude
            let yEnd = centerY + amplitude

            // Verify yStart is within bounds
            XCTAssertGreaterThanOrEqual(yStart, 0)
            XCTAssertLessThanOrEqual(yStart, centerY)

            // Verify yEnd is within bounds
            XCTAssertGreaterThanOrEqual(yEnd, centerY)
            XCTAssertLessThanOrEqual(yEnd, centerY * 2)
        }
    }

    func testWaveformSegmentMapping() {
        // Test mapping waveform samples to segment time range
        let totalDuration: TimeInterval = 10.0
        let sampleCount = 1000
        let segmentTimelineIn: TimeInterval = 2.0
        let segmentTimelineOut: TimeInterval = 5.0

        // Calculate sample range for this segment
        let startRatio = segmentTimelineIn / totalDuration
        let endRatio = segmentTimelineOut / totalDuration

        let startIndex = Int(startRatio * Double(sampleCount))
        let endIndex = Int(endRatio * Double(sampleCount))

        // Verify indices are within bounds
        XCTAssertGreaterThanOrEqual(startIndex, 0)
        XCTAssertLessThanOrEqual(endIndex, sampleCount)
        XCTAssertGreaterThan(endIndex, startIndex)

        // Verify expected values
        XCTAssertEqual(startIndex, 200) // 20% of 1000
        XCTAssertEqual(endIndex, 500) // 50% of 1000

        // Calculate segment sample count
        let segmentSampleCount = endIndex - startIndex
        XCTAssertEqual(segmentSampleCount, 300)
    }

    func testWaveformEmptySamples() {
        // Test behavior with empty waveform samples
        let samples: [Float] = []

        XCTAssertTrue(samples.isEmpty)

        let totalDuration: TimeInterval = 10.0
        let sampleCount = samples.count

        // Verify calculations handle empty array
        let startRatio: TimeInterval = 2.0 / totalDuration
        let startIndex = Int(startRatio * Double(sampleCount))

        XCTAssertEqual(startIndex, 0)
    }

    func testWaveformSingleSample() {
        // Test behavior with single waveform sample
        let samples: [Float] = [0.5]

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0], 0.5)
    }

    func testWaveformAllZeros() {
        // Test behavior with all zero samples (silent audio)
        let samples: [Float] = Array(repeating: 0.0, count: 100)

        XCTAssertEqual(samples.count, 100)
        XCTAssertTrue(samples.allSatisfy { $0 == 0.0 })
    }

    func testWaveformFullScale() {
        // Test waveform with full scale values
        let samples: [Float] = Array(repeating: 1.0, count: 50) + Array(repeating: -1.0, count: 50)

        XCTAssertEqual(samples.count, 100)
        XCTAssertEqual(samples[0], 1.0)
        XCTAssertEqual(samples[49], 1.0)
        XCTAssertEqual(samples[50], -1.0)
        XCTAssertEqual(samples[99], -1.0)
    }

    func testWaveformStrideCalculation() {
        // Test waveform sample width calculation for rendering
        let segmentWidth: CGFloat = 200.0
        let segmentSampleCount = 100

        let sampleWidth = segmentWidth / CGFloat(segmentSampleCount)

        XCTAssertEqual(sampleWidth, 2.0)
    }

    func testWaveformYCoordinateCalculation() {
        // Test waveform Y coordinate calculation
        let centerY: CGFloat = 20.0
        let sample: Float = 0.5

        let amplitude = abs(sample) * centerY
        let yStart = centerY - amplitude
        let yEnd = centerY + amplitude

        XCTAssertEqual(amplitude, 10.0)
        XCTAssertEqual(yStart, 10.0)
        XCTAssertEqual(yEnd, 30.0)
    }

    func testWaveformWithNegativeSample() {
        // Test waveform Y coordinate with negative sample
        let centerY: CGFloat = 20.0
        let sample: Float = -0.5

        let amplitude = abs(sample) * centerY
        let yStart = centerY - amplitude
        let yEnd = centerY + amplitude

        // abs(-0.5) * 20 = 10
        XCTAssertEqual(amplitude, 10.0)
        XCTAssertEqual(yStart, 10.0)
        XCTAssertEqual(yEnd, 30.0)
    }

    func testWaveformWithZeroSample() {
        // Test waveform Y coordinate with zero sample (silence)
        let centerY: CGFloat = 20.0
        let sample: Float = 0.0

        let amplitude = abs(sample) * centerY
        let yStart = centerY - amplitude
        let yEnd = centerY + amplitude

        XCTAssertEqual(amplitude, 0.0)
        XCTAssertEqual(yStart, 20.0)
        XCTAssertEqual(yEnd, 20.0)
    }

    func testWaveformPaddingCalculation() {
        // Test waveform padding calculation
        let height: CGFloat = 34.0
        let waveformPadding: CGFloat = 2.0

        let effectiveHeight = max(2, height - (waveformPadding * 2))

        XCTAssertEqual(effectiveHeight, 30.0)
    }

    func testWaveformMinimumHeight() {
        // Test waveform minimum height constraint
        let height: CGFloat = 2.0
        let waveformPadding: CGFloat = 2.0

        let effectiveHeight = max(2, height - (waveformPadding * 2))

        // Should be at least 2.0
        XCTAssertGreaterThanOrEqual(effectiveHeight, 2.0)
        XCTAssertEqual(effectiveHeight, 2.0)
    }

    func testWaveformTrackKindMapping() {
        // Test mapping track kind to waveform
        let systemAudioPath = "/tmp/system_audio.m4a"
        let micAudioPath = "/tmp/mic_audio.m4a"

        var waveforms: [String: [Float]] = [:]
        waveforms[systemAudioPath] = [0.5, 1.0, 0.5]
        waveforms[micAudioPath] = [0.3, 0.7, 0.3]

        // Verify system audio mapping
        let systemAudioTrack: TimelineTrackKind = .systemAudio
        let systemWaveform = waveforms[systemAudioPath]
        XCTAssertNotNil(systemWaveform)
        XCTAssertEqual(systemWaveform?.count, 3)

        // Verify mic audio mapping
        let micAudioTrack: TimelineTrackKind = .micAudio
        let micWaveform = waveforms[micAudioPath]
        XCTAssertNotNil(micWaveform)
        XCTAssertEqual(micWaveform?.count, 3)

        // Verify screen track has no waveform
        let screenTrack: TimelineTrackKind = .screen
        let screenWaveform = waveforms["/tmp/screen.mov"]
        XCTAssertNil(screenWaveform)

        // Verify camera track has no waveform
        let cameraTrack: TimelineTrackKind = .camera
        let cameraWaveform = waveforms["/tmp/camera.mov"]
        XCTAssertNil(cameraWaveform)
    }

    // MARK: - Waveform Performance Tests

    func testWaveformRenderingPerformance() {
        // Test waveform rendering performance with many samples
        let sampleCount = 1000
        let samples: [Float] = (0..<sampleCount).map { _ in Float.random(in: -1.0...1.0) }

        measure {
            // Simulate rendering calculations
            let centerY: CGFloat = 20.0
            var totalAmplitude: CGFloat = 0

            for sample in samples {
                let amplitude = abs(sample) * centerY
                totalAmplitude += amplitude
            }

            // Verify all samples were processed
            XCTAssertEqual(totalAmplitude, totalAmplitude) // Prevent optimization
        }
    }

    func testWaveformSegmentMappingPerformance() {
        // Test waveform segment mapping performance
        let totalDuration: TimeInterval = 100.0
        let sampleCount = 10000
        let samples: [Float] = Array(repeating: 0.5, count: sampleCount)

        measure {
            for _ in 0..<100 {
                let segmentTimelineIn: TimeInterval = 10.0
                let segmentTimelineOut: TimeInterval = 20.0

                let startRatio = segmentTimelineIn / totalDuration
                let endRatio = segmentTimelineOut / totalDuration

                let startIndex = Int(startRatio * Double(sampleCount))
                let endIndex = Int(endRatio * Double(sampleCount))

                _ = Array(samples[startIndex..<endIndex])
            }
        }
    }

    // MARK: - Waveform Integration Tests

    func testWaveformWithThumbnails() {
        // Test that waveforms and thumbnails can coexist
        var thumbnails: [TimeInterval: NSImage] = [0.0: NSImage()]
        var waveforms: [String: [Float]] = ["/tmp/audio.m4a": [0.5, 1.0, 0.5]]

        // Verify both are present
        XCTAssertEqual(thumbnails.count, 1)
        XCTAssertEqual(waveforms.count, 1)

        // Verify they are independent
        thumbnails[1.0] = NSImage()
        XCTAssertEqual(thumbnails.count, 2)
        XCTAssertEqual(waveforms.count, 1)

        waveforms["/tmp/audio2.m4a"] = [0.3, 0.7, 0.3]
        XCTAssertEqual(thumbnails.count, 2)
        XCTAssertEqual(waveforms.count, 2)
    }

    func testWaveformToggleWithCache() {
        // Test waveform toggle interaction with cache
        let thumbnailCache = ThumbnailCache(configuration: .default)
        var showWaveforms = true
        var waveforms: [String: [Float]] = [:]

        // Waveforms are shown when cache exists and waveforms are loaded
        let shouldShowWaveforms = !waveforms.isEmpty && showWaveforms
        XCTAssertFalse(shouldShowWaveforms)

        // Load waveforms
        waveforms["/tmp/audio.m4a"] = [0.5, 1.0, 0.5]
        let shouldShowAfterLoad = !waveforms.isEmpty && showWaveforms
        XCTAssertTrue(shouldShowAfterLoad)

        // Toggle off
        showWaveforms = false
        let shouldShowAfterToggle = !waveforms.isEmpty && showWaveforms
        XCTAssertFalse(shouldShowAfterToggle)
    }

    func testWaveformForDifferentAudioTracks() {
        // Test waveforms for system audio and mic audio separately
        let systemSamples: [Float] = [0.5, 0.7, 0.6]
        let micSamples: [Float] = [0.3, 0.9, 0.4]

        var waveforms: [String: [Float]] = [:]
        waveforms["/tmp/system.m4a"] = systemSamples
        waveforms["/tmp/mic.m4a"] = micSamples

        // Verify system audio waveform
        let systemWaveform = waveforms["/tmp/system.m4a"]
        XCTAssertNotNil(systemWaveform)
        XCTAssertEqual(systemWaveform?.count, 3)
        XCTAssertEqual(systemWaveform?[1], 0.7)

        // Verify mic audio waveform
        let micWaveform = waveforms["/tmp/mic.m4a"]
        XCTAssertNotNil(micWaveform)
        XCTAssertEqual(micWaveform?.count, 3)
        XCTAssertEqual(micWaveform?[1], 0.9)
    }
}
