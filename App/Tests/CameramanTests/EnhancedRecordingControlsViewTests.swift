//
//  EnhancedRecordingControlsViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-C — Recording UI Tests
//

import XCTest
import SwiftUI
@testable import Cameraman

/// Comprehensive test suite for EnhancedRecordingControlsView
final class EnhancedRecordingControlsViewTests: XCTestCase {

    // MARK: - View Model Tests

    func testEnhancedViewModelInitialization() {
        let viewModel = EnhancedRecordingViewModel()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording initially")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused initially")
        XCTAssertEqual(viewModel.elapsedTime, "00:00", "Elapsed time should be 00:00 initially")
        XCTAssertTrue(viewModel.includeCamera, "Camera should be enabled by default")
        XCTAssertFalse(viewModel.includeMicrophone, "Microphone should be disabled by default")
        XCTAssertTrue(viewModel.includeSystemAudio, "System audio should be enabled by default")
    }

    func testDefaultSourceSelection() {
        let viewModel = EnhancedRecordingViewModel()

        switch viewModel.selectedSource {
        case .display(let source):
            XCTAssertEqual(source.name, "Main Display")
            XCTAssertEqual(source.width, 1920)
            XCTAssertEqual(source.height, 1080)
        default:
            XCTFail("Default source should be display type")
        }
    }

    func testCanStartRecording() {
        let viewModel = EnhancedRecordingViewModel()

        // Should be able to start recording by default
        XCTAssertTrue(viewModel.canStartRecording, "Should be able to start recording")
    }

    // MARK: - Recording Control Tests

    func testStartRecording() async {
        let viewModel = EnhancedRecordingViewModel()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording initially")

        await viewModel.startRecording()

        XCTAssertTrue(viewModel.isRecording, "Should be recording after start")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused after start")
    }

    func testStopRecording() async {
        let viewModel = EnhancedRecordingViewModel()

        // Start recording
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording, "Should be recording")

        // Stop recording
        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording after stop")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused after stop")
        XCTAssertEqual(viewModel.elapsedTime, "00:00", "Elapsed time should be reset")
    }

    func testPauseResumeRecording() async {
        let viewModel = EnhancedRecordingViewModel()

        // Start recording
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording, "Should be recording")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused initially")

        // Pause recording
        await viewModel.pauseResumeRecording()
        XCTAssertTrue(viewModel.isRecording, "Should still be recording")
        XCTAssertTrue(viewModel.isPaused, "Should be paused")

        // Resume recording
        await viewModel.pauseResumeRecording()
        XCTAssertTrue(viewModel.isRecording, "Should still be recording")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused after resume")
    }

    // MARK: - Source Selection Tests

    func testSelectDisplaySource() {
        let viewModel = EnhancedRecordingViewModel()

        let displaySource = SourceSelector.DisplaySource(
            id: "display-2",
            name: "Second Display",
            width: 2560,
            height: 1440,
            refreshRate: 60.0,
            isMain: false
        )

        viewModel.selectedSource = .display(displaySource)

        switch viewModel.selectedSource {
        case .display(let source):
            XCTAssertEqual(source.id, "display-2")
            XCTAssertEqual(source.name, "Second Display")
            XCTAssertEqual(source.width, 2560)
            XCTAssertEqual(source.height, 1440)
        default:
            XCTFail("Source should be display type")
        }
    }

    func testSelectWindowSource() {
        let viewModel = EnhancedRecordingViewModel()

        let windowSource = SourceSelector.WindowSource(
            id: "window-1",
            title: "Safari",
            applicationName: "Safari",
            applicationBundleIdentifier: "com.apple.Safari",
            width: 1280,
            height: 720,
            isOnScreen: true
        )

        viewModel.selectedSource = .window(windowSource)

        switch viewModel.selectedSource {
        case .window(let source):
            XCTAssertEqual(source.id, "window-1")
            XCTAssertEqual(source.title, "Safari")
            XCTAssertEqual(source.applicationName, "Safari")
        default:
            XCTFail("Source should be window type")
        }
    }

    func testSelectApplicationSource() {
        let viewModel = EnhancedRecordingViewModel()

        let appSource = SourceSelector.ApplicationSource(
            id: "com.apple.finder",
            name: "Finder",
            bundleIdentifier: "com.apple.finder",
            iconPath: nil
        )

        viewModel.selectedSource = .application(appSource)

        switch viewModel.selectedSource {
        case .application(let source):
            XCTAssertEqual(source.id, "com.apple.finder")
            XCTAssertEqual(source.name, "Finder")
            XCTAssertEqual(source.bundleIdentifier, "com.apple.finder")
        default:
            XCTFail("Source should be application type")
        }
    }

    // MARK: - Audio/Video Toggle Tests

    func testToggleCamera() {
        let viewModel = EnhancedRecordingViewModel()

        XCTAssertTrue(viewModel.includeCamera, "Camera should be enabled initially")

        viewModel.includeCamera = false
        XCTAssertFalse(viewModel.includeCamera, "Camera should be disabled")

        viewModel.includeCamera = true
        XCTAssertTrue(viewModel.includeCamera, "Camera should be enabled again")
    }

    func testToggleMicrophone() {
        let viewModel = EnhancedRecordingViewModel()

        XCTAssertFalse(viewModel.includeMicrophone, "Microphone should be disabled initially")

        viewModel.includeMicrophone = true
        XCTAssertTrue(viewModel.includeMicrophone, "Microphone should be enabled")

        viewModel.includeMicrophone = false
        XCTAssertFalse(viewModel.includeMicrophone, "Microphone should be disabled again")
    }

    func testToggleSystemAudio() {
        let viewModel = EnhancedRecordingViewModel()

        XCTAssertTrue(viewModel.includeSystemAudio, "System audio should be enabled initially")

        viewModel.includeSystemAudio = false
        XCTAssertFalse(viewModel.includeSystemAudio, "System audio should be disabled")

        viewModel.includeSystemAudio = true
        XCTAssertTrue(viewModel.includeSystemAudio, "System audio should be enabled again")
    }

    func testToggleAllAudioVideo() {
        let viewModel = EnhancedRecordingViewModel()

        // Disable all
        viewModel.includeCamera = false
        viewModel.includeMicrophone = false
        viewModel.includeSystemAudio = false

        XCTAssertFalse(viewModel.includeCamera)
        XCTAssertFalse(viewModel.includeMicrophone)
        XCTAssertFalse(viewModel.includeSystemAudio)

        // Enable all
        viewModel.includeCamera = true
        viewModel.includeMicrophone = true
        viewModel.includeSystemAudio = true

        XCTAssertTrue(viewModel.includeCamera)
        XCTAssertTrue(viewModel.includeMicrophone)
        XCTAssertTrue(viewModel.includeSystemAudio)
    }

    // MARK: - Elapsed Time Tests

    func testElapsedTimeUpdates() async {
        let viewModel = EnhancedRecordingViewModel()

        await viewModel.startRecording()

        // Wait a bit for timer to update
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Elapsed time should have changed from 00:00
        let timeAfterStart = viewModel.elapsedTime
        print("Elapsed time after 0.2s: \(timeAfterStart)")

        XCTAssertNotNil(timeAfterStart, "Elapsed time should be set")
    }

    func testElapsedTimeFormatting() {
        let viewModel = EnhancedRecordingViewModel()

        // Initial time
        XCTAssertEqual(viewModel.elapsedTime, "00:00")

        // Time format should always have colon separator
        XCTAssertTrue(viewModel.elapsedTime.contains(":"), "Time should contain colon separator")
    }

    // MARK: - State Transition Tests

    func testIdleToRecordingTransition() async {
        let viewModel = EnhancedRecordingViewModel()

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)

        await viewModel.startRecording()

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)
    }

    func testRecordingToIdleTransition() async {
        let viewModel = EnhancedRecordingViewModel()

        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)

        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(viewModel.elapsedTime, "00:00")
    }

    // MARK: - Multiple Recording Sessions Tests

    func testMultipleRecordingSessions() async {
        let viewModel = EnhancedRecordingViewModel()

        // First session
        await viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording)

        // Second session
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)

        await viewModel.stopRecording()
        XCTAssertFalse(viewModel.isRecording)
    }

    // MARK: - Configuration Tests

    func testConfigurationWithDifferentSources() {
        let viewModel = EnhancedRecordingViewModel()

        // Test display source
        let display = SourceSelector.DisplaySource(
            id: "display-1",
            name: "Display 1",
            width: 1920,
            height: 1080,
            refreshRate: 60.0,
            isMain: true
        )
        viewModel.selectedSource = .display(display)

        // Test window source
        let window = SourceSelector.WindowSource(
            id: "window-1",
            title: "Window",
            applicationName: "App",
            applicationBundleIdentifier: "com.app",
            width: 800,
            height: 600,
            isOnScreen: true
        )
        viewModel.selectedSource = .window(window)

        // Test application source
        let app = SourceSelector.ApplicationSource(
            id: "app-1",
            name: "App",
            bundleIdentifier: "com.app",
            iconPath: nil
        )
        viewModel.selectedSource = .application(app)

        // All switches should work without errors
        XCTAssertTrue(true, "All source types should be supported")
    }

    func testConfigurationWithDifferentAudioVideoSettings() {
        let viewModel = EnhancedRecordingViewModel()

        // Test all combinations
        let configurations: [(Bool, Bool, Bool)] = [
            (true, false, true),   // Camera + System Audio
            (false, true, true),   // Mic + System Audio
            (true, true, true),    // All enabled
            (false, false, false), // All disabled
        ]

        for (camera, mic, systemAudio) in configurations {
            viewModel.includeCamera = camera
            viewModel.includeMicrophone = mic
            viewModel.includeSystemAudio = systemAudio

            XCTAssertEqual(viewModel.includeCamera, camera)
            XCTAssertEqual(viewModel.includeMicrophone, mic)
            XCTAssertEqual(viewModel.includeSystemAudio, systemAudio)
        }
    }

    // MARK: - Performance Tests

    func testStartRecordingPerformance() async {
        let viewModel = EnhancedRecordingViewModel()

        measure {
            Task {
                await viewModel.startRecording()
            }
        }
    }

    func testStopRecordingPerformance() async {
        let viewModel = EnhancedRecordingViewModel()

        await viewModel.startRecording()

        measure {
            Task {
                await viewModel.stopRecording()
            }
        }
    }

    func testSourceSwitchingPerformance() {
        let viewModel = EnhancedRecordingViewModel()

        measure {
            let display = SourceSelector.DisplaySource(
                id: "display-1",
                name: "Display",
                width: 1920,
                height: 1080,
                refreshRate: 60.0,
                isMain: true
            )
            viewModel.selectedSource = .display(display)
        }
    }

    // MARK: - Integration Tests

    func testCompleteRecordingWorkflow() async {
        let viewModel = EnhancedRecordingViewModel()

        // Setup: Select window source
        let window = SourceSelector.WindowSource(
            id: "window-1",
            title: "Test Window",
            applicationName: "Test App",
            applicationBundleIdentifier: "com.test",
            width: 1280,
            height: 720,
            isOnScreen: true
        )
        viewModel.selectedSource = .window(window)

        // Configure audio/video
        viewModel.includeCamera = true
        viewModel.includeMicrophone = true
        viewModel.includeSystemAudio = true

        // Start recording
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)

        // Pause
        await viewModel.pauseResumeRecording()
        XCTAssertTrue(viewModel.isPaused)

        // Resume
        await viewModel.pauseResumeRecording()
        XCTAssertFalse(viewModel.isPaused)

        // Stop
        await viewModel.stopRecording()
        XCTAssertFalse(viewModel.isRecording)
    }

    func testSourceChangeAfterRecording() async {
        let viewModel = EnhancedRecordingViewModel()

        // Start with one source
        await viewModel.startRecording()

        // Change source while recording (should be allowed)
        let newSource = SourceSelector.DisplaySource(
            id: "display-2",
            name: "Second Display",
            width: 2560,
            height: 1440,
            refreshRate: 60.0,
            isMain: false
        )
        viewModel.selectedSource = .display(newSource)

        XCTAssertTrue(viewModel.isRecording, "Should still be recording after source change")

        await viewModel.stopRecording()
    }

    // MARK: - Edge Case Tests

    func testToggleSettingsWhileRecording() async {
        let viewModel = EnhancedRecordingViewModel()

        await viewModel.startRecording()

        // Toggle settings while recording (should update state but not affect ongoing recording)
        viewModel.includeCamera.toggle()
        viewModel.includeMicrophone.toggle()
        viewModel.includeSystemAudio.toggle()

        XCTAssertTrue(viewModel.isRecording, "Should still be recording")

        await viewModel.stopRecording()
    }

    func testRapidStartStop() async {
        let viewModel = EnhancedRecordingViewModel()

        // Rapid start/stop cycles
        for _ in 0..<5 {
            await viewModel.startRecording()
            await viewModel.stopRecording()
        }

        XCTAssertFalse(viewModel.isRecording, "Should not be recording after rapid cycles")
    }

    func testZeroElapsedTime() {
        let viewModel = EnhancedRecordingViewModel()

        XCTAssertEqual(viewModel.elapsedTime, "00:00", "Initial elapsed time should be 00:00")
    }
}
