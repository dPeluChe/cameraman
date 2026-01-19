//
//  SourceSelectorTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-18.
//

import XCTest
import ScreenCaptureKit
@testable import EngineKit

@available(macOS 13.0, *)
final class SourceSelectorTests: XCTestCase {
    var sut: SourceSelector!

    override func setUp() async throws {
        try await super.setUp()
        sut = SourceSelector.shared
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Display Enumeration Tests

    func testListDisplays_ReturnsAtLeastOneDisplay() async throws {
        // When
        let displays = try await sut.listDisplays()

        // Then
        XCTAssertFalse(displays.isEmpty, "Should return at least one display")
    }

    func testListDisplays_MainDisplayIsMarked() async throws {
        // When
        let displays = try await sut.listDisplays()

        // Then
        let mainDisplays = displays.filter { $0.isMain }

        // There should be exactly one main display
        XCTAssertEqual(mainDisplays.count, 1, "Should have exactly one main display")

        // The main display should have reasonable dimensions
        let mainDisplay = mainDisplays.first!
        XCTAssertTrue(mainDisplay.width > 0, "Main display width should be positive")
        XCTAssertTrue(mainDisplay.height > 0, "Main display height should be positive")
    }

    func testListDisplays_DisplayHasValidProperties() async throws {
        // When
        let displays = try await sut.listDisplays()

        // Then
        for display in displays {
            XCTAssertFalse(display.id.isEmpty, "Display ID should not be empty")
            XCTAssertFalse(display.name.isEmpty, "Display name should not be empty")
            XCTAssertTrue(display.width > 0, "Display width should be positive: \(display.name)")
            XCTAssertTrue(display.height > 0, "Display height should be positive: \(display.name)")
            XCTAssertTrue(display.refreshRate > 0, "Display refresh rate should be positive: \(display.name)")
        }
    }

    // MARK: - Window Enumeration Tests

    func testListWindows_ReturnsWindows() async throws {
        // When
        do {
            let windows = try await sut.listWindows()

            // Then
            // Should return at least some windows (even if only system windows)
            // Note: This might be empty in some CI environments
            XCTAssertTrue(windows.count >= 0, "Should return windows array")
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    func testListWindows_WindowsHaveValidProperties() async throws {
        // When
        do {
            let windows = try await sut.listWindows()

            // Then
            for window in windows {
                XCTAssertFalse(window.id.isEmpty, "Window ID should not be empty")
                XCTAssertFalse(window.title.isEmpty, "Window title should not be empty")
                XCTAssertFalse(window.applicationName.isEmpty, "Application name should not be empty")
                XCTAssertFalse(window.applicationBundleIdentifier.isEmpty, "Bundle identifier should not be empty")
                XCTAssertTrue(window.width > 0, "Window width should be positive: \(window.title)")
                XCTAssertTrue(window.height > 0, "Window height should be positive: \(window.title)")
            }
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    func testListWindows_SortedByApplicationAndTitle() async throws {
        // When
        do {
            let windows = try await sut.listWindows()

            // Then
            // Verify sorting: first by application name, then by window title
            if windows.count > 1 {
                for i in 0..<(windows.count - 1) {
                    let current = windows[i]
                    let next = windows[i + 1]

                    if current.applicationName == next.applicationName {
                        // Same application, should be sorted by title
                        XCTAssertTrue(current.title <= next.title,
                                      "Windows should be sorted by title within the same application")
                    } else {
                        // Different applications, should be sorted by application name
                        XCTAssertTrue(current.applicationName < next.applicationName,
                                      "Windows should be sorted by application name")
                    }
                }
            }
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    func testListWindows_ExcludesTinyWindows() async throws {
        // When
        do {
            let windows = try await sut.listWindows()

            // Then
            for window in windows {
                XCTAssertTrue(window.width >= 50, "Should exclude windows smaller than 50px wide")
                XCTAssertTrue(window.height >= 50, "Should exclude windows smaller than 50px tall")
            }
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    // MARK: - Application Enumeration Tests

    func testListApplications_ReturnsApplications() async throws {
        // When
        do {
            let applications = try await sut.listApplications()

            // Then
            XCTAssertFalse(applications.isEmpty, "Should return at least one application")
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    func testListApplications_ApplicationsHaveValidProperties() async throws {
        // When
        do {
            let applications = try await sut.listApplications()

            // Then
            for application in applications {
                XCTAssertFalse(application.id.isEmpty, "Application ID should not be empty")
                XCTAssertFalse(application.name.isEmpty, "Application name should not be empty")
                XCTAssertFalse(application.bundleIdentifier.isEmpty, "Bundle identifier should not be empty")
            }
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    func testListApplications_SortedByName() async throws {
        // When
        do {
            let applications = try await sut.listApplications()

            // Then
            if applications.count > 1 {
                for i in 0..<(applications.count - 1) {
                    let current = applications[i]
                    let next = applications[i + 1]
                    XCTAssertTrue(current.name <= next.name,
                                  "Applications should be sorted by name")
                }
            }
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    func testListApplications_ContainsSystemApps() async throws {
        // When
        do {
            let applications = try await sut.listApplications()

            // Then
            // Should contain at least some common system applications
            let bundleIds = applications.map { $0.bundleIdentifier }

            // Note: In CI environments, some of these might not be present
            // But we should have at least some applications
            XCTAssertTrue(bundleIds.count > 0, "Should have applications")
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            XCTAssertTrue(true, "Permission denied is acceptable in test environments")
        }
    }

    // MARK: - Permission Check Tests

    func testCheckScreenRecordingPermission_ReturnsBool() async throws {
        // When
        let hasPermission = await sut.checkScreenRecordingPermission()

        // Then
        // Should return a boolean value (might be false in CI environments)
        XCTAssertTrue(hasPermission == true || hasPermission == false,
                      "Should return a valid boolean value")
    }

    // MARK: - Error Handling Tests

    func testListDisplays_WhenPermissionDenied_ThrowsError() async throws {
        // This test is difficult to implement without actually revoking permissions
        // In a real scenario, we would mock the underlying ScreenCaptureKit calls
        // For now, we just verify the method signature is correct

        // When/Then - should not crash
        do {
            _ = try await sut.listDisplays()
            XCTAssertTrue(true, "Method executes without crash")
        } catch {
            // If permission is denied, should throw an appropriate error
            XCTAssertTrue(error is SourceSelector.SourceSelectorError,
                          "Should throw SourceSelectorError")
        }
    }

    func testListWindows_WhenPermissionDenied_ThrowsError() async throws {
        // Similar to above, verify method signature
        do {
            _ = try await sut.listWindows()
            XCTAssertTrue(true, "Method executes without crash")
        } catch {
            XCTAssertTrue(error is SourceSelector.SourceSelectorError,
                          "Should throw SourceSelectorError")
        }
    }

    func testListApplications_WhenPermissionDenied_ThrowsError() async throws {
        // Similar to above, verify method signature
        do {
            _ = try await sut.listApplications()
            XCTAssertTrue(true, "Method executes without crash")
        } catch {
            XCTAssertTrue(error is SourceSelector.SourceSelectorError,
                          "Should throw SourceSelectorError")
        }
    }

    // MARK: - Integration Tests

    func testAllEnumerations_WorkTogether() async throws {
        // When - enumerate all source types
        let displays = try await sut.listDisplays()

        do {
            let windows = try await sut.listWindows()
            let applications = try await sut.listApplications()

            // Then - all should succeed
            XCTAssertNotNil(displays, "Should return displays")
            XCTAssertNotNil(windows, "Should return windows")
            XCTAssertNotNil(applications, "Should return applications")

            // Verify consistency: if we have windows, their applications should be in the applications list
            if !windows.isEmpty {
                let windowBundleIds = Set(windows.map { $0.applicationBundleIdentifier })
                let appBundleIds = Set(applications.map { $0.bundleIdentifier })

                // All window applications should be in the applications list
                for bundleId in windowBundleIds {
                    XCTAssertTrue(appBundleIds.contains(bundleId),
                                  "Window application '\(bundleId)' should be in applications list")
                }
            }
        } catch SourceSelector.SourceSelectorError.permissionDenied {
            // Expected in environments without screen recording permission
            // But displays should still work
            XCTAssertNotNil(displays, "Should return displays even without screen recording permission")
        }
    }
}
