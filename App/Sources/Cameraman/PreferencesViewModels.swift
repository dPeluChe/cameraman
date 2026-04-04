//
//  PreferencesViewModels.swift
//  App
//
//  Extracted from PreferencesView+Sections.swift
//  ViewModels for preferences
//

import SwiftUI
import Combine
import EngineKit

@MainActor
class PreferencesViewModel: ObservableObject {
}

@MainActor
class HotkeysPreferencesViewModel: ObservableObject {
    @Published private(set) var hotkeysEnabled = false
    @Published private(set) var registeredHotkeys: [HotkeyManager.Hotkey] = []

    private let hotkeyManager = HotkeyManager.shared

    func loadHotkeys() async {
        hotkeysEnabled = hotkeyManager.getEnabled()
        registeredHotkeys = hotkeyManager.getRegisteredHotkeys()
    }

    func toggleHotkeys() async {
        if hotkeysEnabled {
            hotkeyManager.unregisterAllHotkeys()
            hotkeysEnabled = false
        } else {
            do {
                try hotkeyManager.registerDefaultHotkeys()
                hotkeysEnabled = true
            } catch {
                LogError(.ui, "Failed to register hotkeys: \(error)")
            }
        }
        registeredHotkeys = hotkeyManager.getRegisteredHotkeys()
    }
}
