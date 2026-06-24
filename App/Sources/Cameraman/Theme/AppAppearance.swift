import SwiftUI
import AppKit

/// User-selectable appearance. Applied via `NSApp.appearance` so it covers both
/// SwiftUI scenes and AppKit windows (panels, teleprompter, diagnostics).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` means "follow the OS".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static let storageKey = "appearancePreference"

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    @MainActor static func apply(_ appearance: AppAppearance) {
        NSApp.appearance = appearance.nsAppearance
    }

    /// Apply the persisted preference; call once at launch.
    @MainActor static func applyStored() {
        apply(current)
    }
}
