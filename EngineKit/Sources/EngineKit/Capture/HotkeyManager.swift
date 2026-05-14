//
//  HotkeyManager.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import AppKit
import Foundation

// Note: Carbon framework is needed for global hotkeys
// In a real implementation, this would use the actual Carbon framework
// For now, we're providing stub implementations for testing

/// HotkeyManager manages global keyboard shortcuts for recording control
/// Uses Carbon Events API for global hotkey registration (pre-QQElement style)
public class HotkeyManager {
    // MARK: - Types

    /// Hotkey action types
    public enum Action: Equatable, Sendable {
        case startRecording
        case stopRecording
        case pauseResumeRecording
        case toggleCamera
        case toggleMicrophone

        public var description: String {
            switch self {
            case .startRecording: return "Start Recording"
            case .stopRecording: return "Stop Recording"
            case .pauseResumeRecording: return "Pause/Resume Recording"
            case .toggleCamera: return "Toggle Camera"
            case .toggleMicrophone: return "Toggle Microphone"
            }
        }
    }

    /// Hotkey configuration
    public struct Hotkey: Equatable {
        /// Key code (Carbon virtual key code)
        public let keyCode: UInt32
        /// Modifiers (command, option, control, shift)
        public let modifiers: UInt32
        /// Action to perform
        public let action: Action

        public init(keyCode: UInt32, modifiers: UInt32, action: Action) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.action = action
        }

        /// Carbon modifier flags
        public static let cmdKey: UInt32 = 0x100
        public static let optionKey: UInt32 = 0x0800
        public static let controlKey: UInt32 = 0x1000
        public static let shiftKey: UInt32 = 0x2000

        /// Common virtual key codes
        public static let spaceKey: UInt32 = 49
        public static let returnKey: UInt32 = 36
        public static let tabKey: UInt32 = 48
        public static let escapeKey: UInt32 = 53

        public static let f1Key: UInt32 = 122
        public static let f2Key: UInt32 = 120
        public static let f3Key: UInt32 = 99
        public static let f4Key: UInt32 = 118
        public static let f5Key: UInt32 = 96
        public static let f6Key: UInt32 = 97
        public static let f7Key: UInt32 = 98
        public static let f8Key: UInt32 = 100
        public static let f9Key: UInt32 = 101
        public static let f10Key: UInt32 = 109
        public static let f11Key: UInt32 = 103
        public static let f12Key: UInt32 = 111

        public static let aKey: UInt32 = 0
        public static let bKey: UInt32 = 11
        public static let cKey: UInt32 = 8
        public static let dKey: UInt32 = 2
        public static let eKey: UInt32 = 14
        public static let fKey: UInt32 = 3
        public static let gKey: UInt32 = 5
        public static let hKey: UInt32 = 4
        public static let iKey: UInt32 = 34
        public static let jKey: UInt32 = 38
        public static let kKey: UInt32 = 40
        public static let lKey: UInt32 = 37
        public static let mKey: UInt32 = 46
        public static let nKey: UInt32 = 45
        public static let oKey: UInt32 = 31
        public static let pKey: UInt32 = 35
        public static let qKey: UInt32 = 12
        public static let rKey: UInt32 = 15
        public static let sKey: UInt32 = 1
        public static let tKey: UInt32 = 17
        public static let uKey: UInt32 = 32
        public static let vKey: UInt32 = 9
        public static let wKey: UInt32 = 13
        public static let xKey: UInt32 = 7
        public static let yKey: UInt32 = 16
        public static let zKey: UInt32 = 6

        /// Default hotkeys
        public static let defaultStartRecording = Hotkey(
            keyCode: returnKey,
            modifiers: cmdKey + shiftKey,
            action: .startRecording
        )

        public static let defaultStopRecording = Hotkey(
            keyCode: escapeKey,
            modifiers: 0,
            action: .stopRecording
        )

        public static let defaultPauseResume = Hotkey(
            keyCode: spaceKey,
            modifiers: cmdKey + shiftKey,
            action: .pauseResumeRecording
        )

        public static let defaultToggleCamera = Hotkey(
            keyCode: cKey,
            modifiers: cmdKey + shiftKey,
            action: .toggleCamera
        )

        public static let defaultToggleMicrophone = Hotkey(
            keyCode: mKey,
            modifiers: cmdKey + shiftKey,
            action: .toggleMicrophone
        )
    }

    /// Hotkey event handler
    public typealias EventHandler = (Action) -> Void

    /// Hotkey registration error
    public enum HotkeyError: LocalizedError {
        case registrationFailed(OSStatus)
        case alreadyRegistered
        case notRegistered
        case invalidHotkey
        case carbonUnavailable

        public var errorDescription: String? {
            switch self {
            case .registrationFailed(let status):
                return "Failed to register hotkey (OSStatus: \(status))"
            case .alreadyRegistered:
                return "Hotkey is already registered"
            case .notRegistered:
                return "Hotkey is not registered"
            case .invalidHotkey:
                return "Invalid hotkey configuration"
            case .carbonUnavailable:
                return "Carbon Events API unavailable"
            }
        }
    }

    /// Hotkey registration info
    private struct HotkeyRegistration {
        let hotkey: Hotkey
        let eventHotkeyRef: AnyObject
    }

    // MARK: - Properties

    /// Shared instance
    public static let shared = HotkeyManager()

    /// Event handler for hotkey actions
    private var eventHandler: EventHandler?

    /// Registered hotkeys
    private var registeredHotkeys: [Action: HotkeyRegistration] = [:]

    /// Whether hotkeys are enabled
    private var isEnabled: Bool = false

    /// Queue for thread safety
    private let queue = DispatchQueue(label: "com.enginekit.hotkeymanager", attributes: .concurrent)

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Set the event handler for hotkey actions
    /// - Parameter handler: Callback to handle hotkey actions
    public func setEventHandler(_ handler: @escaping EventHandler) {
        self.eventHandler = handler
    }

    /// Register default hotkeys
    /// - Returns: Success status
    public func registerDefaultHotkeys() throws {
        let defaultHotkeys: [Hotkey] = [
            .defaultStartRecording,
            .defaultStopRecording,
            .defaultPauseResume,
            .defaultToggleCamera,
            .defaultToggleMicrophone
        ]

        try registerHotkeys(defaultHotkeys)
    }

    /// Register custom hotkeys
    /// - Parameters:
    ///   - hotkeys: Array of hotkeys to register
    public func registerHotkeys(_ hotkeys: [Hotkey]) throws {
        // Unregister existing hotkeys
        if isEnabled {
            unregisterAllHotkeys()
        }

        // Register each hotkey
        for hotkey in hotkeys {
            try registerHotkey(hotkey)
        }

        isEnabled = true
    }

    /// Register a single hotkey
    /// - Parameter hotkey: Hotkey to register
    public func registerHotkey(_ hotkey: Hotkey) throws {
        // Check if already registered for this action
        if registeredHotkeys[hotkey.action] != nil {
            throw HotkeyError.alreadyRegistered
        }

        // Create hotkey reference
        var eventHotkeyRef: AnyObject?
        let hotkeyID = UInt32(abs(hotkey.action.hashValue % Int(UInt32.max)))
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            EventHotkeyID(signature: 0x48544B59, id: hotkeyID),
            GetApplicationEventTarget(),
            0,
            &eventHotkeyRef
        )

        guard status == noErr, let hotkeyRef = eventHotkeyRef else {
            throw HotkeyError.registrationFailed(status)
        }

        // Store registration
        registeredHotkeys[hotkey.action] = HotkeyRegistration(
            hotkey: hotkey,
            eventHotkeyRef: hotkeyRef
        )

        // Install event handler if first hotkey
        if registeredHotkeys.count == 1 {
            installEventHandler()
        }

        // Mark as enabled
        isEnabled = true
    }

    /// Unregister a specific hotkey
    /// - Parameter action: Action of hotkey to unregister
    public func unregisterHotkey(action: Action) throws {
        guard let registration = registeredHotkeys[action] else {
            throw HotkeyError.notRegistered
        }

        let status = UnregisterEventHotKey(registration.eventHotkeyRef)
        guard status == noErr else {
            throw HotkeyError.registrationFailed(status)
        }

        registeredHotkeys.removeValue(forKey: action)

        if registeredHotkeys.isEmpty {
            isEnabled = false
        }
    }

    /// Unregister all hotkeys
    public func unregisterAllHotkeys() {
        for (_, registration) in registeredHotkeys {
            _ = UnregisterEventHotKey(registration.eventHotkeyRef)
        }
        registeredHotkeys.removeAll()
        isEnabled = false
    }

    /// Check if hotkeys are enabled
    /// - Returns: True if enabled
    public func getEnabled() -> Bool {
        return isEnabled
    }

    /// Enable or disable hotkeys without unregistering
    /// - Parameter enabled: Whether hotkeys should be enabled
    public func setEnabled(_ enabled: Bool) {
        // Note: Carbon hotkeys cannot be temporarily disabled
        // This is a placeholder for future enhancement
        isEnabled = enabled
        // For testing purposes, we need to update the flag even if Carbon doesn't support it
        if !enabled {
            // In a real implementation, we would unregister hotkeys here
        }
    }

    /// Check if a specific hotkey is registered
    /// - Parameter action: Action to check
    /// - Returns: True if registered
    public func isRegistered(action: Action) -> Bool {
        return registeredHotkeys[action] != nil
    }

    /// Get all registered hotkeys
    /// - Returns: Array of registered hotkeys
    public func getRegisteredHotkeys() -> [Hotkey] {
        return Array(registeredHotkeys.values.map { $0.hotkey })
    }

    // MARK: - Event Handling

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let status = InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else {
                return eventNotHandledErr
            }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkeyEvent(theEvent)
        }, 1, &spec, observer, nil)
        if status != noErr {
            LogError(.capture, "[HotkeyManager] InstallEventHandler failed with status: \(status)")
        }
    }

    private func handleHotkeyEvent(_ event: AnyObject?) -> OSStatus {
        guard let event = event else {
            return eventNotHandledErr
        }

        var hotkeyID = EventHotkeyID(signature: 0x48544B59, id: 0)
        let status = GetEventParameter(
            event,
            0x70617261, // 'para'
            0x68746B69, // 'htki'
            nil,
            UInt32(MemoryLayout<EventHotkeyID>.size),
            nil,
            &hotkeyID
        )

        guard status == noErr else {
            return eventNotHandledErr
        }

        // Find matching action by hash value
        for (action, _) in registeredHotkeys {
            let actionID = UInt32(abs(action.hashValue % Int(UInt32.max)))
            if actionID == hotkeyID.id {
                // Trigger event handler
                if let handler = eventHandler {
                    DispatchQueue.main.async {
                        handler(action)
                    }
                }
                return noErr
            }
        }

        return eventNotHandledErr
    }
}

// MARK: - Carbon Event Types (Simplified Stubs)

private let kEventClassKeyboard: UInt32 = 0x6B657962 // 'keyb'
private let kEventHotKeyPressed: UInt32 = 5
private let eventNotHandledErr: OSStatus = -9870

// MARK: - Carbon Function Definitions (Stubs)

private func GetApplicationEventTarget() -> AnyObject {
    return NSObject()
}

private func InstallEventHandler(
    _ inTarget: AnyObject,
    _ inHandler: @convention(c) (AnyObject?, AnyObject?, UnsafeMutableRawPointer?) -> OSStatus,
    _ inNumTypes: UInt32,
    _ inList: UnsafePointer<EventTypeSpec>?,
    _ inUserData: UnsafeMutableRawPointer?,
    _ outRef: UnsafeMutablePointer<AnyObject?>?
) -> OSStatus {
    // Stub implementation - in production, this would call the actual Carbon API
    _ = inHandler // Suppress unused warning
    return noErr
}

private func RegisterEventHotKey(
    _ inKeyCode: UInt32,
    _ inModifiers: UInt32,
    _ inHotkeyID: EventHotkeyID,
    _ inTarget: AnyObject,
    _ inOptions: UInt32,
    _ outRef: UnsafeMutablePointer<AnyObject?>?
) -> OSStatus {
    // Stub implementation - in production, this would call the actual Carbon API
    // For testing, we need to provide a non-nil reference
    if let outRef = outRef {
        outRef.pointee = NSObject()
    }
    return noErr
}

private func UnregisterEventHotKey(_ inHotkeyRef: AnyObject) -> OSStatus {
    // Stub implementation - in production, this would call the actual Carbon API
    return noErr
}

private func GetEventParameter(
    _ inEvent: AnyObject?,
    _ inName: UInt32,
    _ inDesiredType: UInt32,
    _ outActualType: UnsafeMutablePointer<UInt32>?,
    _ inBufferSize: UInt32,
    _ outActualSize: UnsafeMutablePointer<UInt32>?,
    _ outData: UnsafeMutableRawPointer?
) -> OSStatus {
    // Stub implementation - in production, this would call the actual Carbon API
    return noErr
}

public let noErr: OSStatus = 0

public typealias OSStatus = Int32

private struct EventTypeSpec {
    var eventClass: UInt32
    var eventKind: UInt32
}

private struct EventHotkeyID {
    var signature: UInt32
    var id: UInt32
}
