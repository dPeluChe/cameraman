//
//  HotkeyManagerTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Tests for HotkeyManager
/// Note: These tests use stubbed Carbon API implementations
/// In a production environment, actual Carbon events would be tested
final class HotkeyManagerTests: XCTestCase {
    var hotkeyManager: HotkeyManager!

    override func setUp() async throws {
        try await super.setUp()
        hotkeyManager = HotkeyManager.shared
        // Ensure clean state
        hotkeyManager.unregisterAllHotkeys()
    }

    override func tearDown() async throws {
        // Cleanup
        hotkeyManager.unregisterAllHotkeys()
        try await super.tearDown()
    }

    // MARK: - Default Hotkeys

    func testDefaultHotkeyDefinitions() throws {
        // Test that default hotkeys are defined
        let defaultStart = HotkeyManager.Hotkey.defaultStartRecording
        let defaultStop = HotkeyManager.Hotkey.defaultStopRecording
        let defaultPause = HotkeyManager.Hotkey.defaultPauseResume

        XCTAssertEqual(defaultStart.action, .startRecording)
        XCTAssertEqual(defaultStop.action, .stopRecording)
        XCTAssertEqual(defaultPause.action, .pauseResumeRecording)
    }

    func testDefaultStartRecordingHotkey() throws {
        let hotkey = HotkeyManager.Hotkey.defaultStartRecording
        XCTAssertEqual(hotkey.keyCode, HotkeyManager.Hotkey.returnKey)
        XCTAssertEqual(hotkey.modifiers, HotkeyManager.Hotkey.cmdKey + HotkeyManager.Hotkey.shiftKey)
        XCTAssertEqual(hotkey.action, .startRecording)
    }

    func testDefaultStopRecordingHotkey() throws {
        let hotkey = HotkeyManager.Hotkey.defaultStopRecording
        XCTAssertEqual(hotkey.keyCode, HotkeyManager.Hotkey.escapeKey)
        XCTAssertEqual(hotkey.modifiers, 0)
        XCTAssertEqual(hotkey.action, .stopRecording)
    }

    func testDefaultPauseResumeHotkey() throws {
        let hotkey = HotkeyManager.Hotkey.defaultPauseResume
        XCTAssertEqual(hotkey.keyCode, HotkeyManager.Hotkey.spaceKey)
        XCTAssertEqual(hotkey.modifiers, HotkeyManager.Hotkey.cmdKey + HotkeyManager.Hotkey.shiftKey)
        XCTAssertEqual(hotkey.action, .pauseResumeRecording)
    }

    // MARK: - Hotkey Registration

    func testRegisterSingleHotkey() async throws {
        // Note: This test uses stubbed Carbon API, so actual hotkey events won't be triggered
        // In production, the event handler would be called when the hotkey is pressed
        let hotkey = HotkeyManager.Hotkey(
            keyCode: HotkeyManager.Hotkey.f1Key,
            modifiers: HotkeyManager.Hotkey.cmdKey,
            action: .startRecording
        )

        hotkeyManager.setEventHandler { action in
            XCTAssertEqual(action, .startRecording)
        }

        try hotkeyManager.registerHotkey(hotkey)

        XCTAssertTrue(hotkeyManager.isRegistered(action: .startRecording))
    }

    func testRegisterMultipleHotkeys() async throws {
        let hotkeys: [HotkeyManager.Hotkey] = [
            HotkeyManager.Hotkey(keyCode: HotkeyManager.Hotkey.f1Key, modifiers: HotkeyManager.Hotkey.cmdKey, action: .startRecording),
            HotkeyManager.Hotkey(keyCode: HotkeyManager.Hotkey.f2Key, modifiers: HotkeyManager.Hotkey.cmdKey, action: .stopRecording),
            HotkeyManager.Hotkey(keyCode: HotkeyManager.Hotkey.f3Key, modifiers: HotkeyManager.Hotkey.cmdKey, action: .pauseResumeRecording)
        ]

        var receivedActions: [HotkeyManager.Action] = []
        hotkeyManager.setEventHandler { action in
            receivedActions.append(action)
        }

        try hotkeyManager.registerHotkeys(hotkeys)

        XCTAssertTrue(hotkeyManager.isRegistered(action: .startRecording))
        XCTAssertTrue(hotkeyManager.isRegistered(action: .stopRecording))
        XCTAssertTrue(hotkeyManager.isRegistered(action: .pauseResumeRecording))
    }

    func testRegisterDefaultHotkeys() async throws {
        var startCalled = false
        var stopCalled = false
        var pauseCalled = false

        hotkeyManager.setEventHandler { action in
            switch action {
            case .startRecording:
                startCalled = true
            case .stopRecording:
                stopCalled = true
            case .pauseResumeRecording:
                pauseCalled = true
            default:
                break
            }
        }

        try hotkeyManager.registerDefaultHotkeys()

        XCTAssertTrue(hotkeyManager.isRegistered(action: .startRecording))
        XCTAssertTrue(hotkeyManager.isRegistered(action: .stopRecording))
        XCTAssertTrue(hotkeyManager.isRegistered(action: .pauseResumeRecording))
        XCTAssertTrue(hotkeyManager.isRegistered(action: .toggleCamera))
        XCTAssertTrue(hotkeyManager.isRegistered(action: .toggleMicrophone))
    }

    func testRegisterDuplicateHotkeyThrowsError() async throws {
        let hotkey = HotkeyManager.Hotkey(
            keyCode: HotkeyManager.Hotkey.f1Key,
            modifiers: HotkeyManager.Hotkey.cmdKey,
            action: .startRecording
        )

        hotkeyManager.setEventHandler { _ in }

        // First registration should succeed
        try hotkeyManager.registerHotkey(hotkey)

        // Second registration with same action should fail
        do {
            try hotkeyManager.registerHotkey(hotkey)
            XCTFail("Expected HotkeyError.alreadyRegistered")
        } catch HotkeyManager.HotkeyError.alreadyRegistered {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Hotkey Unregistration

    func testUnregisterHotkey() async throws {
        let hotkey = HotkeyManager.Hotkey(
            keyCode: HotkeyManager.Hotkey.f1Key,
            modifiers: HotkeyManager.Hotkey.cmdKey,
            action: .startRecording
        )

        hotkeyManager.setEventHandler { _ in }
        try hotkeyManager.registerHotkey(hotkey)
        XCTAssertTrue(hotkeyManager.isRegistered(action: .startRecording))

        try hotkeyManager.unregisterHotkey(action: .startRecording)
        XCTAssertFalse(hotkeyManager.isRegistered(action: .startRecording))
    }

    func testUnregisterNonExistentHotkeyThrowsError() async throws {
        do {
            try hotkeyManager.unregisterHotkey(action: .startRecording)
            XCTFail("Expected HotkeyError.notRegistered")
        } catch HotkeyManager.HotkeyError.notRegistered {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnregisterAllHotkeys() async throws {
        let hotkeys: [HotkeyManager.Hotkey] = [
            HotkeyManager.Hotkey(keyCode: HotkeyManager.Hotkey.f1Key, modifiers: HotkeyManager.Hotkey.cmdKey, action: .startRecording),
            HotkeyManager.Hotkey(keyCode: HotkeyManager.Hotkey.f2Key, modifiers: HotkeyManager.Hotkey.cmdKey, action: .stopRecording)
        ]

        hotkeyManager.setEventHandler { _ in }
        try hotkeyManager.registerHotkeys(hotkeys)

        hotkeyManager.unregisterAllHotkeys()

        XCTAssertFalse(hotkeyManager.isRegistered(action: .startRecording))
        XCTAssertFalse(hotkeyManager.isRegistered(action: .stopRecording))
        XCTAssertFalse(hotkeyManager.getEnabled())
    }

    // MARK: - Enable/Disable

    func testSetEnabled() async throws {
        let hotkey = HotkeyManager.Hotkey(
            keyCode: HotkeyManager.Hotkey.f1Key,
            modifiers: HotkeyManager.Hotkey.cmdKey,
            action: .startRecording
        )

        hotkeyManager.setEventHandler { _ in }
        try hotkeyManager.registerHotkey(hotkey)

        XCTAssertTrue(hotkeyManager.getEnabled())

        hotkeyManager.setEnabled(false)
        XCTAssertFalse(hotkeyManager.getEnabled())

        hotkeyManager.setEnabled(true)
        XCTAssertTrue(hotkeyManager.getEnabled())
    }

    // MARK: - Get Registered Hotkeys

    func testGetRegisteredHotkeys() async throws {
        let hotkeys: [HotkeyManager.Hotkey] = [
            HotkeyManager.Hotkey(keyCode: HotkeyManager.Hotkey.f1Key, modifiers: HotkeyManager.Hotkey.cmdKey, action: .startRecording),
            HotkeyManager.Hotkey(keyCode: HotkeyManager.Hotkey.f2Key, modifiers: HotkeyManager.Hotkey.cmdKey, action: .stopRecording)
        ]

        hotkeyManager.setEventHandler { _ in }
        try hotkeyManager.registerHotkeys(hotkeys)

        let registered = hotkeyManager.getRegisteredHotkeys()
        XCTAssertEqual(registered.count, 2)
    }

    func testGetRegisteredHotkeysEmpty() async throws {
        let registered = hotkeyManager.getRegisteredHotkeys()
        XCTAssertEqual(registered.count, 0)
    }

    // MARK: - Action Descriptions

    func testActionDescriptions() {
        XCTAssertEqual(HotkeyManager.Action.startRecording.description, "Start Recording")
        XCTAssertEqual(HotkeyManager.Action.stopRecording.description, "Stop Recording")
        XCTAssertEqual(HotkeyManager.Action.pauseResumeRecording.description, "Pause/Resume Recording")
        XCTAssertEqual(HotkeyManager.Action.toggleCamera.description, "Toggle Camera")
        XCTAssertEqual(HotkeyManager.Action.toggleMicrophone.description, "Toggle Microphone")
    }

    // MARK: - Virtual Key Codes

    func testVirtualKeyCodes() {
        // Test that virtual key codes are defined
        // Note: aKey is 0 in Carbon virtual key code mapping, which is valid
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.spaceKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.returnKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.escapeKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.tabKey, 0)

        // Function keys
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f1Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f2Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f3Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f4Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f5Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f6Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f7Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f8Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f9Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f10Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f11Key, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.f12Key, 0)

        // Letter keys
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.aKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.bKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.cKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.mKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.rKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.sKey, 0)
        XCTAssertGreaterThanOrEqual(HotkeyManager.Hotkey.zKey, 0)
    }

    // MARK: - Modifier Flags

    func testModifierFlags() {
        XCTAssertGreaterThan(HotkeyManager.Hotkey.cmdKey, 0)
        XCTAssertGreaterThan(HotkeyManager.Hotkey.optionKey, 0)
        XCTAssertGreaterThan(HotkeyManager.Hotkey.controlKey, 0)
        XCTAssertGreaterThan(HotkeyManager.Hotkey.shiftKey, 0)

        // Test that modifiers can be combined
        let combined = HotkeyManager.Hotkey.cmdKey + HotkeyManager.Hotkey.shiftKey
        XCTAssertGreaterThan(combined, 0)
        XCTAssertNotEqual(combined, HotkeyManager.Hotkey.cmdKey)
        XCTAssertNotEqual(combined, HotkeyManager.Hotkey.shiftKey)
    }

    // MARK: - Error Descriptions

    func testErrorDescriptions() {
        let alreadyRegistered = HotkeyManager.HotkeyError.alreadyRegistered
        XCTAssertEqual(alreadyRegistered.errorDescription, "Hotkey is already registered")

        let notRegistered = HotkeyManager.HotkeyError.notRegistered
        XCTAssertEqual(notRegistered.errorDescription, "Hotkey is not registered")

        let invalidHotkey = HotkeyManager.HotkeyError.invalidHotkey
        XCTAssertEqual(invalidHotkey.errorDescription, "Invalid hotkey configuration")

        let carbonUnavailable = HotkeyManager.HotkeyError.carbonUnavailable
        XCTAssertEqual(carbonUnavailable.errorDescription, "Carbon Events API unavailable")
    }

    // MARK: - Performance

    func testHotkeyRegistrationPerformance() throws {
        measure {
            let hotkey = HotkeyManager.Hotkey(
                keyCode: HotkeyManager.Hotkey.f1Key,
                modifiers: HotkeyManager.Hotkey.cmdKey,
                action: .startRecording
            )

            // Register/unregister multiple times
            for _ in 0..<100 {
                hotkeyManager.setEventHandler { _ in }
                _ = try? hotkeyManager.registerHotkey(hotkey)
                _ = try? hotkeyManager.unregisterHotkey(action: .startRecording)
            }
        }
    }
}
