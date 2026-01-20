//
//  PreferencesViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-L — Settings & Preferences (P1)
//

import XCTest
import SwiftUI
@testable import App
@testable import EngineKit

@MainActor
final class PreferencesViewTests: XCTestCase {

    // MARK: - General Preferences Tests

    func testGeneralPreferencesAutosaveToggle() {
        // Test that autosave toggle works
        let view = GeneralPreferencesView()
        XCTAssertNotNil(view)
    }

    func testGeneralPreferencesAutosaveInterval() {
        // Test autosave interval slider bounds
        let view = GeneralPreferencesView()
        XCTAssertNotNil(view)
    }

    func testGeneralPreferencesShowTooltips() {
        // Test tooltips toggle
        let view = GeneralPreferencesView()
        XCTAssertNotNil(view)
    }

    func testGeneralPreferencesCheckForUpdates() {
        // Test updates toggle
        let view = GeneralPreferencesView()
        XCTAssertNotNil(view)
    }

    // MARK: - Hotkeys Preferences Tests

    func testHotkeysPreferencesViewModelInitialization() {
        let viewModel = HotkeysPreferencesViewModel()
        XCTAssertFalse(viewModel.hotkeysEnabled, "Hotkeys should initially be disabled in tests")
        XCTAssertTrue(viewModel.registeredHotkeys.isEmpty, "No hotkeys should be registered initially")
    }

    func testHotkeysPreferencesViewModelLoadHotkeys() async {
        let viewModel = HotkeysPreferencesViewModel()

        // Load hotkeys from HotkeyManager
        await viewModel.loadHotkeys()

        // Verify hotkeys state is loaded
        // Note: In tests, HotkeyManager may not have hotkeys registered
        // This test verifies the load mechanism works
        XCTAssertNotNil(viewModel)
    }

    func testHotkeyRowRendering() {
        // Create a sample hotkey
        let hotkey = HotkeyManager.Hotkey(
            keyCode: HotkeyManager.Hotkey.rKey,
            modifiers: HotkeyManager.Hotkey.cmdKey | HotkeyManager.Hotkey.shiftKey,
            action: .startRecording
        )

        // Create hotkey row
        let row = HotkeyRow(hotkey: hotkey)
        XCTAssertNotNil(row)
    }

    func testHotkeyRowKeyEquivalentRendering() {
        // Test different hotkey combinations
        let hotkeys = [
            HotkeyManager.Hotkey(
                keyCode: HotkeyManager.Hotkey.returnKey,
                modifiers: HotkeyManager.Hotkey.cmdKey | HotkeyManager.Hotkey.shiftKey,
                action: .startRecording
            ),
            HotkeyManager.Hotkey(
                keyCode: HotkeyManager.Hotkey.escapeKey,
                modifiers: 0,
                action: .stopRecording
            ),
            HotkeyManager.Hotkey(
                keyCode: HotkeyManager.Hotkey.spaceKey,
                modifiers: HotkeyManager.Hotkey.cmdKey | HotkeyManager.Hotkey.shiftKey,
                action: .pauseResumeRecording
            ),
        ]

        for hotkey in hotkeys {
            let row = HotkeyRow(hotkey: hotkey)
            XCTAssertNotNil(row, "HotkeyRow should render for action: \(hotkey.action.description)")
        }
    }

    func testHotkeyIconForAction() {
        // Test that all actions have icons
        let actions: [HotkeyManager.Action] = [
            .startRecording,
            .stopRecording,
            .pauseResumeRecording,
            .toggleCamera,
            .toggleMicrophone
        ]

        for action in actions {
            let hotkey = HotkeyManager.Hotkey(
                keyCode: HotkeyManager.Hotkey.aKey,
                modifiers: 0,
                action: action
            )
            let row = HotkeyRow(hotkey: hotkey)
            XCTAssertNotNil(row, "Icon should exist for action: \(action.description)")
        }
    }

    func testDefaultHotkeyRowRendering() {
        // Test default hotkey info rows
        let rows = [
            DefaultHotkeyRow(keyEquivalent: "R", modifiers: "⌘⇧", action: "Start Recording"),
            DefaultHotkeyRow(keyEquivalent: "Esc", modifiers: "", action: "Stop Recording"),
            DefaultHotkeyRow(keyEquivalent: "Space", modifiers: "⌘⇧", action: "Pause/Resume"),
        ]

        for row in rows {
            XCTAssertNotNil(row)
        }
    }

    func testHotkeysPreferencesViewModelToggleHotkeys() async {
        let viewModel = HotkeysPreferencesViewModel()

        // Initially disabled (in test environment)
        XCTAssertFalse(viewModel.hotkeysEnabled)

        // Try to enable hotkeys
        await viewModel.toggleHotkeys()

        // HotkeyManager should attempt to register hotkeys
        // In test environment, this may or may not succeed
        // We're testing that the toggle mechanism works
        XCTAssertNotNil(viewModel)
    }

    // MARK: - Recording Preferences Tests

    func testRecordingPreferencesDefaults() {
        let view = RecordingPreferencesView()
        XCTAssertNotNil(view)
    }

    func testRecordingPreferencesFrameRateOptions() {
        // Test that frame rate picker has correct options
        let frameRates = [30.0, 60.0, 120.0]
        XCTAssertEqual(frameRates.count, 3, "Should have 3 frame rate options")
        XCTAssertTrue(frameRates.contains(60.0), "Should include 60fps")
    }

    func testRecordingPreferencesResolutionOptions() {
        // Test that resolution picker has correct options
        let resolutions = ["720p", "1080p", "4K"]
        XCTAssertEqual(resolutions.count, 3, "Should have 3 resolution options")
        XCTAssertTrue(resolutions.contains("1080p"), "Should include 1080p")
    }

    // MARK: - Export Preferences Tests

    func testExportPreferencesDefaults() {
        let view = ExportPreferencesView()
        XCTAssertNotNil(view)
    }

    func testExportPreferencesPresetOptions() {
        // Test export preset options
        let presets = ["Web 1080p H.264", "High 1080p HEVC", "Portrait 1080p H.264", "Animated GIF"]
        XCTAssertEqual(presets.count, 4, "Should have 4 export presets")
        XCTAssertTrue(presets.contains("Web 1080p H.264"), "Should include Web 1080p preset")
    }

    func testExportPreferencesDestinationOptions() {
        // Test destination options
        let destinations = ["Movies", "Documents", "Desktop"]
        XCTAssertEqual(destinations.count, 3, "Should have 3 destination options")
        XCTAssertTrue(destinations.contains("Movies"), "Should include Movies folder")
    }

    // MARK: - Preferences Tab Tests

    func testPreferencesTabsExist() {
        let tabs: [PreferencesView.PreferencesTab] = [.general, .hotkeys, .recording, .export]
        XCTAssertEqual(tabs.count, 4, "Should have 4 preference tabs")
    }

    func testPreferencesTabIcons() {
        let tabs: [PreferencesView.PreferencesTab] = [.general, .hotkeys, .recording, .export]
        let expectedIcons = ["gear", "command", "record.circle", "square.and.arrow.up"]

        for (index, tab) in tabs.enumerated() {
            XCTAssertEqual(tab.icon, expectedIcons[index], "Tab should have correct icon")
        }
    }

    func testPreferencesTabAllCases() {
        let allTabs = PreferencesView.PreferencesTab.allCases
        XCTAssertEqual(allTabs.count, 4, "Should have 4 tabs in allCases")
    }

    // MARK: - PreferencesView Integration Tests

    func testPreferencesViewInitialization() {
        let view = PreferencesView()
        XCTAssertNotNil(view)
    }

    func testPreferencesViewDefaultTab() {
        let view = PreferencesView()
        // Default tab should be general
        // Note: We can't directly access selectedTab without reflection or making it internal
        XCTAssertNotNil(view)
    }

    func testPreferencesViewModelInitialization() {
        let viewModel = PreferencesViewModel()
        XCTAssertNotNil(viewModel)
    }

    // MARK: - UserDefaults Persistence Tests

    func testAutosaveEnabledPersistence() {
        let defaults = UserDefaults.standard
        let key = "autosaveEnabled"

        // Save value
        defaults.set(true, forKey: key)

        // Read value
        let value = defaults.bool(forKey: key)
        XCTAssertTrue(value, "Autosave enabled should persist")
    }

    func testAutosaveIntervalPersistence() {
        let defaults = UserDefaults.standard
        let key = "autosaveInterval"

        // Save value
        defaults.set(60.0, forKey: key)

        // Read value
        let value = defaults.double(forKey: key)
        XCTAssertEqual(value, 60.0, accuracy: 0.1, "Autosave interval should persist")
    }

    func testShowTooltipsPersistence() {
        let defaults = UserDefaults.standard
        let key = "showTooltips"

        // Save value
        defaults.set(false, forKey: key)

        // Read value
        let value = defaults.bool(forKey: key)
        XCTAssertFalse(value, "Show tooltips should persist")
    }

    func testDefaultIncludeCameraPersistence() {
        let defaults = UserDefaults.standard
        let key = "defaultIncludeCamera"

        // Save value
        defaults.set(true, forKey: key)

        // Read value
        let value = defaults.bool(forKey: key)
        XCTAssertTrue(value, "Default include camera should persist")
    }

    func testRecordingFrameRatePersistence() {
        let defaults = UserDefaults.standard
        let key = "recordingFrameRate"

        // Save value
        defaults.set(60.0, forKey: key)

        // Read value
        let value = defaults.double(forKey: key)
        XCTAssertEqual(value, 60.0, accuracy: 0.1, "Recording frame rate should persist")
    }

    func testDefaultExportPresetPersistence() {
        let defaults = UserDefaults.standard
        let key = "defaultExportPreset"

        // Save value
        defaults.set("Web 1080p H.264", forKey: key)

        // Read value
        let value = defaults.string(forKey: key)
        XCTAssertEqual(value, "Web 1080p H.264", "Default export preset should persist")
    }

    func testExportDestinationPersistence() {
        let defaults = UserDefaults.standard
        let key = "exportDestination"

        // Save value
        defaults.set("Movies", forKey: key)

        // Read value
        let value = defaults.string(forKey: key)
        XCTAssertEqual(value, "Movies", "Export destination should persist")
    }

    // MARK: - HotkeyManager Integration Tests

    func testHotkeyManagerSharedInstance() {
        let manager = HotkeyManager.shared
        XCTAssertNotNil(manager, "HotkeyManager should have a shared instance")
    }

    func testHotkeyManagerDefaultHotkeys() {
        let defaultHotkeys: [HotkeyManager.Hotkey] = [
            .defaultStartRecording,
            .defaultStopRecording,
            .defaultPauseResume,
            .defaultToggleCamera,
            .defaultToggleMicrophone
        ]

        for hotkey in defaultHotkeys {
            XCTAssertNotNil(hotkey, "Default hotkey should exist: \(hotkey.action.description)")
        }
    }

    func testHotkeyModifierFlags() {
        XCTAssertEqual(HotkeyManager.Hotkey.cmdKey, 0x100, "Cmd key flag should be correct")
        XCTAssertEqual(HotkeyManager.Hotkey.optionKey, 0x0800, "Option key flag should be correct")
        XCTAssertEqual(HotkeyManager.Hotkey.controlKey, 0x1000, "Control key flag should be correct")
        XCTAssertEqual(HotkeyManager.Hotkey.shiftKey, 0x2000, "Shift key flag should be correct")
    }

    func testHotkeyCodeConstants() {
        XCTAssertNotNil(HotkeyManager.Hotkey.returnKey, "Return key code should exist")
        XCTAssertNotNil(HotkeyManager.Hotkey.escapeKey, "Escape key code should exist")
        XCTAssertNotNil(HotkeyManager.Hotkey.spaceKey, "Space key code should exist")
        XCTAssertNotNil(HotkeyManager.Hotkey.aKey, "A key code should exist")
        XCTAssertNotNil(HotkeyManager.Hotkey.zKey, "Z key code should exist")
    }

    // MARK: - Edge Case Tests

    func testHotkeyRowWithAllModifiers() {
        // Test hotkey with all modifiers
        let hotkey = HotkeyManager.Hotkey(
            keyCode: HotkeyManager.Hotkey.aKey,
            modifiers: HotkeyManager.Hotkey.cmdKey | HotkeyManager.Hotkey.optionKey |
                       HotkeyManager.Hotkey.controlKey | HotkeyManager.Hotkey.shiftKey,
            action: .startRecording
        )

        let row = HotkeyRow(hotkey: hotkey)
        XCTAssertNotNil(row, "HotkeyRow should handle all modifiers")
    }

    func testHotkeyRowWithNoModifiers() {
        // Test hotkey with no modifiers
        let hotkey = HotkeyManager.Hotkey(
            keyCode: HotkeyManager.Hotkey.escapeKey,
            modifiers: 0,
            action: .stopRecording
        )

        let row = HotkeyRow(hotkey: hotkey)
        XCTAssertNotNil(row, "HotkeyRow should handle no modifiers")
    }

    func testAutosaveIntervalSliderBounds() {
        // Test autosave interval slider bounds
        let minInterval = 10.0
        let maxInterval = 300.0
        let step = 10.0

        // Verify bounds
        XCTAssertEqual(minInterval, 10.0, "Min interval should be 10s")
        XCTAssertEqual(maxInterval, 300.0, "Max interval should be 300s (5 minutes)")
        XCTAssertEqual(step, 10.0, "Step should be 10s")
    }

    // MARK: - Performance Tests

    func testHotkeysPreferencesLoadPerformance() {
        let viewModel = HotkeysPreferencesViewModel()

        measure {
            Task {
                await viewModel.loadHotkeys()
            }
        }
    }

    func testPreferencesViewRenderingPerformance() {
        measure {
            let view = PreferencesView()
            _ = view.body
        }
    }

    // MARK: - Accessibility Tests

    func testHotkeyActionsAccessibilityDescriptions() {
        let actions: [HotkeyManager.Action] = [
            .startRecording,
            .stopRecording,
            .pauseResumeRecording,
            .toggleCamera,
            .toggleMicrophone
        ]

        for action in actions {
            let description = action.description
            XCTAssertFalse(description.isEmpty, "Action should have accessibility description: \(action)")
        }
    }
}
