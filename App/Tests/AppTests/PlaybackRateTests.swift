//
//  PlaybackRateTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import XCTest
import AVFoundation
@testable import App
@testable import EngineKit

@MainActor
final class PlaybackRateTests: XCTestCase {
    var viewModel: PreviewPlayerViewModel!
    var testProject: Project!
    var testProjectDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        viewModel = PreviewPlayerViewModel()

        // Create a test project
        testProject = Project(
            projectId: "test-project",
            createdAt: Date(),
            updatedAt: Date(),
            timeline: Project.Timeline(
                segments: [
                    Project.Timeline.Segment(
                        id: "segment-1",
                        sourceId: "screen",
                        sourceIn: 0,
                        sourceOut: 10,
                        speed: 1.0
                    )
                ]
            ),
            sources: Project.Sources(
                screen: Project.Sources.Source(
                    path: "test_screen.mov",
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    duration: 10.0
                ),
                camera: nil,
                systemAudio: nil,
                micAudio: nil
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(w: 1920, h: 1080),
                layout: .pip,
                background: .solid(color: "#000000")
            ),
            overlays: [],
            captions: nil
        )

        // Create temporary directory for test project
        let tempDir = FileManager.default.temporaryDirectory
        testProjectDirectory = tempDir.appendingPathComponent("test_project_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testProjectDirectory, withIntermediateDirectories: true)

        // Create a dummy screen recording file
        let screenPath = testProjectDirectory.appendingPathComponent("test_screen.mov")
        try Data().write(to: screenPath)
    }

    override func tearDown() async throws {
        viewModel = nil
        testProject = nil

        // Clean up test directory
        if let testProjectDirectory = testProjectDirectory {
            try? FileManager.default.removeItem(at: testProjectDirectory)
        }

        try await super.tearDown()
    }

    // MARK: - PlaybackRate Enum Tests

    func testPlaybackRateEnumValues() {
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.half.rawValue, 0.5)
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.normal.rawValue, 1.0)
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.double.rawValue, 2.0)
    }

    func testPlaybackRateDisplayNames() {
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.half.displayName, "0.5x")
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.normal.displayName, "1x")
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.double.displayName, "2x")
    }

    func testPlaybackRateIdentifiable() {
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.half.id, 0.5)
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.normal.id, 1.0)
        XCTAssertEqual(PreviewPlayerViewModel.PlaybackRate.double.id, 2.0)
    }

    func testPlaybackRateIterable() {
        let allRates = PreviewPlayerViewModel.PlaybackRate.allCases
        XCTAssertEqual(allRates.count, 3)
        XCTAssertTrue(allRates.contains(.half))
        XCTAssertTrue(allRates.contains(.normal))
        XCTAssertTrue(allRates.contains(.double))
    }

    // MARK: - PlaybackRate State Tests

    func testDefaultPlaybackRate() {
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    func testSetPlaybackRateToHalf() {
        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)
    }

    func testSetPlaybackRateToNormal() {
        viewModel.setPlaybackRate(.normal)
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    func testSetPlaybackRateToDouble() {
        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)
    }

    func testPlaybackRateChanges() {
        XCTAssertEqual(viewModel.playbackRate, .normal)

        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        viewModel.setPlaybackRate(.normal)
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    // MARK: - PlaybackRate with Player Tests

    func testSetPlaybackRateWithoutPlayer() {
        // Setting rate without a player should not crash and should update the state
        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)
    }

    func testSetPlaybackRateWithLoadedProject() async {
        // Load a project (which creates a player if the file exists)
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Set playback rate
        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        viewModel.setPlaybackRate(.normal)
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    // MARK: - PlaybackRate Reset Tests

    func testResetClearsPlaybackRate() {
        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        viewModel.reset()
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    // MARK: - PlaybackRate Toggle PlayPause Integration Tests

    func testTogglePlayPauseWithNormalRate() async {
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Set normal rate
        viewModel.setPlaybackRate(.normal)

        // Toggle play/pause multiple times
        viewModel.togglePlayPause()
        // Note: Without actual video file, player might not be created, so we just test the method doesn't crash
        viewModel.togglePlayPause()
    }

    func testTogglePlayPauseWithHalfRate() async {
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Set half rate
        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        // Toggle play/pause
        viewModel.togglePlayPause()
        viewModel.togglePlayPause()
    }

    func testTogglePlayPauseWithDoubleRate() async {
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Set double rate
        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        // Toggle play/pause
        viewModel.togglePlayPause()
        viewModel.togglePlayPause()
    }

    func testTogglePlayPauseChangesRate() async {
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Set half rate and play
        viewModel.setPlaybackRate(.half)
        viewModel.togglePlayPause()

        // Change rate while playing
        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        // Stop
        viewModel.togglePlayPause()
    }

    // MARK: - PlaybackRate Edge Cases Tests

    func testPlaybackRatePersistenceAcrossLoad() async {
        // Set a rate
        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        // Load a project
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Rate should remain the same
        XCTAssertEqual(viewModel.playbackRate, .half)
    }

    func testPlaybackRateWithReset() async {
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Set a rate
        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        // Reset
        viewModel.reset()

        // Rate should be back to normal
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    func testPlaybackRateWithNilProject() async {
        // Set a rate
        viewModel.setPlaybackRate(.half)

        // Load nil project
        viewModel.load(project: nil, projectDirectory: nil)

        // Rate should be reset to normal
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    // MARK: - PlaybackRate UI Integration Tests

    func testPlaybackRatePickerOptions() {
        let allRates = PreviewPlayerViewModel.PlaybackRate.allCases
        XCTAssertEqual(allRates.count, 3)

        // Verify order is correct for UI display
        XCTAssertEqual(allRates[0], .half)
        XCTAssertEqual(allRates[1], .normal)
        XCTAssertEqual(allRates[2], .double)
    }

    func testPlaybackRateDisplayFormat() {
        // Verify display names are properly formatted
        XCTAssertTrue(PreviewPlayerViewModel.PlaybackRate.half.displayName.contains("0.5"))
        XCTAssertTrue(PreviewPlayerViewModel.PlaybackRate.normal.displayName.contains("1"))
        XCTAssertTrue(PreviewPlayerViewModel.PlaybackRate.double.displayName.contains("2"))
    }

    // MARK: - Performance Tests

    func testPlaybackRateSwitchingPerformance() {
        measure {
            for _ in 0..<100 {
                viewModel.setPlaybackRate(.half)
                viewModel.setPlaybackRate(.normal)
                viewModel.setPlaybackRate(.double)
            }
        }
    }

    func testPlaybackRateTogglePerformance() {
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        measure {
            for _ in 0..<100 {
                viewModel.setPlaybackRate(.half)
                viewModel.togglePlayPause()
                viewModel.togglePlayPause()
                viewModel.setPlaybackRate(.double)
            }
        }
    }

    // MARK: - Integration Test Scenarios

    func testUserWorkflow_NormalSpeed() async {
        // User workflow: Watch at normal speed
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)
        XCTAssertEqual(viewModel.playbackRate, .normal)

        // Play
        viewModel.togglePlayPause()

        // Pause
        viewModel.togglePlayPause()

        // Rate should still be normal
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    func testUserWorkflow_FastForward() async {
        // User workflow: Watch at 2x speed
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Change to 2x
        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        // Play
        viewModel.togglePlayPause()

        // Pause
        viewModel.togglePlayPause()

        // Rate should still be 2x
        XCTAssertEqual(viewModel.playbackRate, .double)
    }

    func testUserWorkflow_SlowMotion() async {
        // User workflow: Watch at 0.5x speed for detailed review
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Change to 0.5x
        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        // Play
        viewModel.togglePlayPause()

        // Pause
        viewModel.togglePlayPause()

        // Rate should still be 0.5x
        XCTAssertEqual(viewModel.playbackRate, .half)
    }

    func testUserWorkflow_ChangeSpeedWhilePlaying() async {
        // User workflow: Start at normal, then speed up
        viewModel.load(project: testProject, projectDirectory: testProjectDirectory)

        // Start playing at normal speed
        viewModel.togglePlayPause()

        // Change to 2x while playing
        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        // Pause
        viewModel.togglePlayPause()

        // Change back to normal
        viewModel.setPlaybackRate(.normal)
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }
}
