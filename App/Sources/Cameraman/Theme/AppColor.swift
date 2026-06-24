import SwiftUI
import AppKit

extension Color {
    /// Adaptive color resolved at render time against the active appearance.
    /// Use only for brand surfaces that have no fitting system color.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Semantic palette for app chrome. Maps to system colors where possible so
/// light/dark follow the OS; custom surfaces use `Color(light:dark:)`.
/// Not for user content (overlay/subtitle/canvas colors) or video-overlay
/// strokes drawn on top of frames — those stay fixed by design.
enum AppColor {
    // Surfaces
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let underPage = Color(nsColor: .underPageBackgroundColor)

    /// Elevated panel drawn over content (recording selector, custom popovers).
    static let panel = Color(light: NSColor(white: 0.98, alpha: 1.0),
                             dark: NSColor(white: 0.13, alpha: 1.0))
    static let panelTranslucent = Color(light: NSColor(white: 1.0, alpha: 0.92),
                                        dark: NSColor(white: 0.08, alpha: 0.85))
    /// Subtle inset fill for rows/wells.
    static let inset = Color(light: NSColor(white: 0.0, alpha: 0.05),
                             dark: NSColor(white: 1.0, alpha: 0.06))
    static let insetSelected = Color(light: NSColor(white: 0.0, alpha: 0.10),
                                     dark: NSColor(white: 1.0, alpha: 0.12))

    // Text
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // Lines
    static let separator = Color(nsColor: .separatorColor)
    static let border = Color(light: NSColor(white: 0.0, alpha: 0.12),
                              dark: NSColor(white: 1.0, alpha: 0.14))

    /// Dimming scrim for modal/overlay backgrounds.
    static let scrim = Color(light: NSColor(white: 0.0, alpha: 0.35),
                             dark: NSColor(white: 0.0, alpha: 0.55))
}
