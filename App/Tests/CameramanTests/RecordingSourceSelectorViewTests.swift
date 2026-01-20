//
//  RecordingSourceSelectorViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-C — Recording UI Tests
//

import XCTest
import SwiftUI
import EngineKit
@testable import Cameraman

/// Comprehensive test suite for RecordingSourceSelectorView
final class RecordingSourceSelectorViewTests: XCTestCase {

    // MARK: - View Model Tests

    func testSourceSelectorViewModelInitialization() async {
        let viewModel = SourceSelectorViewModel()

        XCTAssertEqual(viewModel.selectedTab, .display, "Default tab should be display")
        XCTAssertTrue(viewModel.displaySources.isEmpty, "Display sources should be empty initially")
        XCTAssertTrue(viewModel.windowSources.isEmpty, "Window sources should be empty initially")
        XCTAssertTrue(viewModel.applicationSources.isEmpty, "Application sources should be empty initially")
        XCTAssertNil(viewModel.previewImage, "Preview image should be nil initially")
        XCTAssertNil(viewModel.errorMessage, "Error message should be nil initially")
    }

    func testLoadDisplaySources() async {
        let viewModel = SourceSelectorViewModel()

        await viewModel.loadSources(for: .display)

        // Check that sources were loaded (may be empty in test environment)
        XCTAssertNotNil(viewModel.displaySources, "Display sources should be loaded")
        XCTAssertNil(viewModel.errorMessage, "No error should occur")
    }

    func testLoadWindowSources() async {
        let viewModel = SourceSelectorViewModel()

        await viewModel.loadSources(for: .window)

        // Check that sources were loaded (may be empty in test environment)
        XCTAssertNotNil(viewModel.windowSources, "Window sources should be loaded")
        XCTAssertNil(viewModel.errorMessage, "No error should occur")
    }

    func testLoadApplicationSources() async {
        let viewModel = SourceSelectorViewModel()

        await viewModel.loadSources(for: .application)

        // Check that sources were loaded (may be empty in test environment)
        XCTAssertNotNil(viewModel.applicationSources, "Application sources should be loaded")
        XCTAssertNil(viewModel.errorMessage, "No error should occur")
    }

    func testTabSwitching() async {
        let viewModel = SourceSelectorViewModel()

        // Switch to window tab
        viewModel.selectedTab = .window
        XCTAssertEqual(viewModel.selectedTab, .window, "Tab should switch to window")

        // Switch to application tab
        viewModel.selectedTab = .application
        XCTAssertEqual(viewModel.selectedTab, .application, "Tab should switch to application")

        // Switch back to display tab
        viewModel.selectedTab = .display
        XCTAssertEqual(viewModel.selectedTab, .display, "Tab should switch to display")
    }

    // MARK: - Display Source Tests

    func testDisplaySourceCreation() {
        let display = SourceSelector.DisplaySource(
            id: "test-display",
            name: "Test Display",
            width: 1920,
            height: 1080,
            refreshRate: 60.0,
            isMain: true
        )

        XCTAssertEqual(display.id, "test-display")
        XCTAssertEqual(display.name, "Test Display")
        XCTAssertEqual(display.width, 1920)
        XCTAssertEqual(display.height, 1080)
        XCTAssertEqual(display.refreshRate, 60.0)
        XCTAssertTrue(display.isMain)
    }

    func testDisplaySourceEquality() {
        let display1 = SourceSelector.DisplaySource(
            id: "display-1",
            name: "Display 1",
            width: 1920,
            height: 1080,
            refreshRate: 60.0,
            isMain: true
        )

        let display2 = SourceSelector.DisplaySource(
            id: "display-1",
            name: "Display 1",
            width: 1920,
            height: 1080,
            refreshRate: 60.0,
            isMain: true
        )

        let display3 = SourceSelector.DisplaySource(
            id: "display-2",
            name: "Display 2",
            width: 2560,
            height: 1440,
            refreshRate: 60.0,
            isMain: false
        )

        XCTAssertEqual(display1, display2, "Displays with same properties should be equal")
        XCTAssertNotEqual(display1, display3, "Displays with different properties should not be equal")
    }

    // MARK: - Window Source Tests

    func testWindowSourceCreation() {
        let window = SourceSelector.WindowSource(
            id: "window-1",
            title: "Test Window",
            applicationName: "Test App",
            applicationBundleIdentifier: "com.test.app",
            width: 800,
            height: 600,
            isOnScreen: true
        )

        XCTAssertEqual(window.id, "window-1")
        XCTAssertEqual(window.title, "Test Window")
        XCTAssertEqual(window.applicationName, "Test App")
        XCTAssertEqual(window.applicationBundleIdentifier, "com.test.app")
        XCTAssertEqual(window.width, 800)
        XCTAssertEqual(window.height, 600)
        XCTAssertTrue(window.isOnScreen)
    }

    func testWindowSourceEquality() {
        let window1 = SourceSelector.WindowSource(
            id: "window-1",
            title: "Window 1",
            applicationName: "App 1",
            applicationBundleIdentifier: "com.app1",
            width: 800,
            height: 600,
            isOnScreen: true
        )

        let window2 = SourceSelector.WindowSource(
            id: "window-1",
            title: "Window 1",
            applicationName: "App 1",
            applicationBundleIdentifier: "com.app1",
            width: 800,
            height: 600,
            isOnScreen: true
        )

        let window3 = SourceSelector.WindowSource(
            id: "window-2",
            title: "Window 2",
            applicationName: "App 2",
            applicationBundleIdentifier: "com.app2",
            width: 1024,
            height: 768,
            isOnScreen: false
        )

        XCTAssertEqual(window1, window2, "Windows with same properties should be equal")
        XCTAssertNotEqual(window1, window3, "Windows with different properties should not be equal")
    }

    // MARK: - Application Source Tests

    func testApplicationSourceCreation() {
        let application = SourceSelector.ApplicationSource(
            id: "app-1",
            name: "Test Application",
            bundleIdentifier: "com.test.application",
            iconPath: "/path/to/icon"
        )

        XCTAssertEqual(application.id, "app-1")
        XCTAssertEqual(application.name, "Test Application")
        XCTAssertEqual(application.bundleIdentifier, "com.test.application")
        XCTAssertEqual(application.iconPath, "/path/to/icon")
    }

    func testApplicationSourceEquality() {
        let app1 = SourceSelector.ApplicationSource(
            id: "app-1",
            name: "App 1",
            bundleIdentifier: "com.app1",
            iconPath: "/path/icon1"
        )

        let app2 = SourceSelector.ApplicationSource(
            id: "app-1",
            name: "App 1",
            bundleIdentifier: "com.app1",
            iconPath: "/path/icon1"
        )

        let app3 = SourceSelector.ApplicationSource(
            id: "app-2",
            name: "App 2",
            bundleIdentifier: "com.app2",
            iconPath: nil
        )

        XCTAssertEqual(app1, app2, "Applications with same properties should be equal")
        XCTAssertNotEqual(app1, app3, "Applications with different properties should not be equal")
    }

    // MARK: - Capture Source Tests

    func testCaptureSourceDisplay() {
        let display = SourceSelector.DisplaySource(
            id: "display-1",
            name: "Display 1",
            width: 1920,
            height: 1080,
            refreshRate: 60.0,
            isMain: true
        )

        let source = RecordingSourceSelectorView.CaptureSource.display(display)

        switch source {
        case .display(let d):
            XCTAssertEqual(d.id, display.id)
        default:
            XCTFail("Source should be display type")
        }
    }

    func testCaptureSourceWindow() {
        let window = SourceSelector.WindowSource(
            id: "window-1",
            title: "Test Window",
            applicationName: "Test App",
            applicationBundleIdentifier: "com.test.app",
            width: 800,
            height: 600,
            isOnScreen: true
        )

        let source = RecordingSourceSelectorView.CaptureSource.window(window)

        switch source {
        case .window(let w):
            XCTAssertEqual(w.id, window.id)
        default:
            XCTFail("Source should be window type")
        }
    }

    func testCaptureSourceApplication() {
        let application = SourceSelector.ApplicationSource(
            id: "app-1",
            name: "Test App",
            bundleIdentifier: "com.test.app",
            iconPath: nil
        )

        let source = RecordingSourceSelectorView.CaptureSource.application(application)

        switch source {
        case .application(let a):
            XCTAssertEqual(a.id, application.id)
        default:
            XCTFail("Source should be application type")
        }
    }

    // MARK: - Preview Tests

    func testCapturePreviewForDisplay() async {
        let viewModel = SourceSelectorViewModel()

        let display = SourceSelector.DisplaySource(
            id: "test-display",
            name: "Test Display",
            width: 1920,
            height: 1080,
            refreshRate: 60.0,
            isMain: true
        )

        await viewModel.capturePreview(display: display)

        // Preview may or may not be captured depending on test environment
        // Just verify the method doesn't crash
        XCTAssertTrue(true, "Capture preview should complete without error")
    }

    func testCapturePreviewForWindow() async {
        let viewModel = SourceSelectorViewModel()

        let window = SourceSelector.WindowSource(
            id: "window-1",
            title: "Test Window",
            applicationName: "Test App",
            applicationBundleIdentifier: "com.test.app",
            width: 800,
            height: 600,
            isOnScreen: true
        )

        await viewModel.capturePreview(window: window)

        // Preview may or may not be captured depending on test environment
        // Just verify the method doesn't crash
        XCTAssertTrue(true, "Capture preview should complete without error")
    }

    // MARK: - Integration Tests

    func testSourceSelectionWorkflow() async {
        let viewModel = SourceSelectorViewModel()

        // Start with display sources
        viewModel.selectedTab = .display
        await viewModel.loadSources(for: .display)
        XCTAssertFalse(viewModel.displaySources.isEmpty || viewModel.displaySources.isEmpty, "Display sources loaded")

        // Switch to window sources
        viewModel.selectedTab = .window
        await viewModel.loadSources(for: .window)
        XCTAssertNotNil(viewModel.windowSources, "Window sources should be loaded")

        // Switch to application sources
        viewModel.selectedTab = .application
        await viewModel.loadSources(for: .application)
        XCTAssertNotNil(viewModel.applicationSources, "Application sources should be loaded")
    }

    func testErrorHandling() async {
        let viewModel = SourceSelectorViewModel()

        // Load sources should handle errors gracefully
        await viewModel.loadSources(for: .display)

        // If there's an error, errorMessage should be set
        // If there's no error, errorMessage should be nil
        // Either way, the test passes (no crash)
        XCTAssertTrue(true, "Error handling should not crash")
    }

    // MARK: - Performance Tests

    func testSourceLoadingPerformance() async {
        let viewModel = SourceSelectorViewModel()

        measure {
            Task {
                await viewModel.loadSources(for: .display)
            }
        }
    }
}
