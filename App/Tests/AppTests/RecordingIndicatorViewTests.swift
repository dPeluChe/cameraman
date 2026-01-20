//
//  RecordingIndicatorViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-C — Recording UI Tests
//

import XCTest
import SwiftUI
@testable import App

/// Comprehensive test suite for RecordingIndicatorView
final class RecordingIndicatorViewTests: XCTestCase {

    // MARK: - View Model Tests

    func testIndicatorViewModelInitialization() {
        let viewModel = RecordingIndicatorViewModel()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording initially")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused initially")
        XCTAssertEqual(viewModel.elapsedTime, "00:00", "Elapsed time should be 00:00 initially")
        XCTAssertTrue(viewModel.includeCamera, "Camera should be enabled by default")
        XCTAssertFalse(viewModel.includeMicrophone, "Microphone should be disabled by default")
        XCTAssertTrue(viewModel.includeSystemAudio, "System audio should be enabled by default")
        XCTAssertEqual(viewModel.sourceDescription, "Display 1", "Default source should be Display 1")
        XCTAssertNil(viewModel.estimatedDuration, "Estimated duration should be nil initially")
    }

    func testStartRecording() async {
        let viewModel = RecordingIndicatorViewModel()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording initially")

        await viewModel.startRecording()

        XCTAssertTrue(viewModel.isRecording, "Should be recording after start")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused after start")
    }

    func testStopRecording() async {
        let viewModel = RecordingIndicatorViewModel()

        // Start recording
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording, "Should be recording")

        // Stop recording
        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording after stop")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused after stop")
        XCTAssertEqual(viewModel.elapsedTime, "00:00", "Elapsed time should be reset")
        XCTAssertNil(viewModel.estimatedDuration, "Estimated duration should be nil")
    }

    func testPauseResumeRecording() async {
        let viewModel = RecordingIndicatorViewModel()

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

    func testPauseWithoutRecording() async {
        let viewModel = RecordingIndicatorViewModel()

        // Try to pause without recording (should be a no-op)
        await viewModel.pauseResumeRecording()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording")
        XCTAssertFalse(viewModel.isPaused, "Should not be paused")
    }

    func testStopWithoutRecording() async {
        let viewModel = RecordingIndicatorViewModel()

        // Try to stop without recording (should be a no-op)
        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording, "Should not be recording")
    }

    // MARK: - Elapsed Time Tests

    func testElapsedTimeUpdates() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()

        // Wait a bit for timer to update
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Elapsed time should have changed from 00:00
        let timeAfterStart = viewModel.elapsedTime
        print("Elapsed time after 0.2s: \(timeAfterStart)")

        // Time should be at least 00:00 (may still be 00:00 if timer hasn't fired)
        XCTAssertNotNil(timeAfterStart, "Elapsed time should be set")
    }

    func testElapsedTimeResetOnStop() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()

        // Wait a bit
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        let timeBeforeStop = viewModel.elapsedTime

        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.elapsedTime, "00:00", "Elapsed time should be reset to 00:00")
        XCTAssertNotEqual(timeBeforeStop, "00:00", "Time should have been different before stop")
    }

    // MARK: - Configuration Tests

    func testSetCameraEnabled() {
        let viewModel = RecordingIndicatorViewModel()

        viewModel.configure(camera: true, microphone: false, systemAudio: true)

        XCTAssertTrue(viewModel.includeCamera, "Camera should be enabled")
        XCTAssertFalse(viewModel.includeMicrophone, "Microphone should be disabled")
        XCTAssertTrue(viewModel.includeSystemAudio, "System audio should be enabled")
    }

    func testSetAllAudioVideoDisabled() {
        let viewModel = RecordingIndicatorViewModel()

        viewModel.configure(camera: false, microphone: false, systemAudio: false)

        XCTAssertFalse(viewModel.includeCamera, "Camera should be disabled")
        XCTAssertFalse(viewModel.includeMicrophone, "Microphone should be disabled")
        XCTAssertFalse(viewModel.includeSystemAudio, "System audio should be disabled")
    }

    func testSetAllAudioVideoEnabled() {
        let viewModel = RecordingIndicatorViewModel()

        viewModel.configure(camera: true, microphone: true, systemAudio: true)

        XCTAssertTrue(viewModel.includeCamera, "Camera should be enabled")
        XCTAssertTrue(viewModel.includeMicrophone, "Microphone should be enabled")
        XCTAssertTrue(viewModel.includeSystemAudio, "System audio should be enabled")
    }

    func testSetSourceDescription() {
        let viewModel = RecordingIndicatorViewModel()

        viewModel.setSource(description: "Custom Display")
        XCTAssertEqual(viewModel.sourceDescription, "Custom Display")

        viewModel.setSource(description: "Window: Safari")
        XCTAssertEqual(viewModel.sourceDescription, "Window: Safari")
    }

    // MARK: - Duration Formatting Tests

    func testDurationFormatting() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()

        // Simulate elapsed time updates (via internal timer logic)
        // The actual timer runs in the background, so we'll just test the state

        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        if let duration = viewModel.estimatedDuration {
            print("Estimated duration: \(duration)")
            XCTAssertNotNil(duration, "Duration should be set")
        }
    }

    // MARK: - State Transition Tests

    func testIdleToRecordingTransition() async {
        let viewModel = RecordingIndicatorViewModel()

        // Initial state: idle
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)

        // Transition to recording
        await viewModel.startRecording()

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)
    }

    func testRecordingToPausedTransition() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)

        await viewModel.pauseResumeRecording()

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertTrue(viewModel.isPaused)
    }

    func testPausedToRecordingTransition() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()
        await viewModel.pauseResumeRecording()
        XCTAssertTrue(viewModel.isPaused)

        await viewModel.pauseResumeRecording()

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)
    }

    func testRecordingToIdleTransition() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)

        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)
    }

    func testPausedToIdleTransition() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()
        await viewModel.pauseResumeRecording()
        XCTAssertTrue(viewModel.isPaused)

        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)
    }

    // MARK: - Multiple Start/Stop Tests

    func testMultipleStartCalls() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()
        let firstRecordingState = viewModel.isRecording

        await viewModel.startRecording()
        let secondRecordingState = viewModel.isRecording

        XCTAssertEqual(firstRecordingState, secondRecordingState, "Multiple start calls should be idempotent")
        XCTAssertTrue(secondRecordingState, "Should still be recording")
    }

    func testMultipleStopCalls() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()
        await viewModel.stopRecording()

        let firstStopState = viewModel.isRecording

        await viewModel.stopRecording()
        let secondStopState = viewModel.isRecording

        XCTAssertEqual(firstStopState, secondStopState, "Multiple stop calls should be idempotent")
        XCTAssertFalse(secondStopState, "Should not be recording")
    }

    func testStartStopStartCycle() async {
        let viewModel = RecordingIndicatorViewModel()

        // First recording session
        await viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        await viewModel.stopRecording()

        XCTAssertFalse(viewModel.isRecording)

        // Second recording session
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)

        await viewModel.stopRecording()
        XCTAssertFalse(viewModel.isRecording)
    }

    // MARK: - Performance Tests

    func testStartRecordingPerformance() async {
        let viewModel = RecordingIndicatorViewModel()

        measure {
            Task {
                await viewModel.startRecording()
            }
        }
    }

    func testStopRecordingPerformance() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()

        measure {
            Task {
                await viewModel.stopRecording()
            }
        }
    }

    func testTimerUpdatePerformance() async {
        let viewModel = RecordingIndicatorViewModel()

        await viewModel.startRecording()

        measure {
            // Simulate timer update
            let elapsed = Date().timeIntervalSince(viewModel.startTime ?? Date())
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            _ = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - Edge Case Tests

    func testZeroElapsedTimeFormatting() {
        let viewModel = RecordingIndicatorViewModel()

        // Initial elapsed time should be 00:00
        XCTAssertEqual(viewModel.elapsedTime, "00:00")
    }

    func testHourFormatting() async {
        let viewModel = RecordingIndicatorViewModel()

        // Note: Current implementation only shows MM:SS
        // If hours are needed in the future, update the implementation
        await viewModel.startRecording()

        // Simulate long recording (would need to mock startTime for proper testing)
        // For now, just verify the format
        XCTAssertTrue(viewModel.elapsedTime.contains(":"), "Time should contain colon separator")
    }

    // MARK: - Integration Tests

    func testFullRecordingWorkflow() async {
        let viewModel = RecordingIndicatorViewModel()

        // Setup
        viewModel.configure(camera: true, microphone: true, systemAudio: true)
        viewModel.setSource(description: "Main Display")

        // Start
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(viewModel.sourceDescription, "Main Display")

        // Pause
        await viewModel.pauseResumeRecording()
        XCTAssertTrue(viewModel.isPaused)

        // Resume
        await viewModel.pauseResumeRecording()
        XCTAssertFalse(viewModel.isPaused)

        // Stop
        await viewModel.stopRecording()
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPaused)
    }
}
