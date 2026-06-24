import SwiftUI

/// Spacing scale — use everywhere instead of ad-hoc literals.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

/// Corner-radius scale.
enum Radius {
    static let small: CGFloat = 6   // buttons, badges, inline wells
    static let medium: CGFloat = 8  // cards, sections (default)
    static let large: CGFloat = 12  // large surfaces, sheets
}

/// Standard modal/window sizes. Migration maps each window to one of these.
enum ModalSize {
    case small      // confirmations, pickers
    case medium     // settings-like, single-purpose dialogs
    case large      // multi-section dialogs
    case xlarge     // list + detail dialogs

    var size: CGSize {
        switch self {
        case .small:  return CGSize(width: 440, height: 420)
        case .medium: return CGSize(width: 580, height: 480)
        case .large:  return CGSize(width: 680, height: 560)
        case .xlarge: return CGSize(width: 760, height: 640)
        }
    }
}

extension View {
    /// Fixed frame for a standard modal size.
    func modalFrame(_ size: ModalSize) -> some View {
        frame(width: size.size.width, height: size.size.height)
    }

    /// Wrap content as a standard section card (padding + control background + radius).
    func sectionCard(padding: CGFloat = Spacing.lg) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.controlBackground)
            .cornerRadius(Radius.medium)
    }
}
