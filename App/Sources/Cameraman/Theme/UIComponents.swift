import SwiftUI

/// A titled settings/inspector section: header (+ optional subtitle) over content,
/// wrapped in a standard card. Replaces the ad-hoc
/// `VStack { Text(...).font(.headline); ... }.padding().background(...).cornerRadius(8)`
/// pattern repeated across Preferences and panels.
struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(_ title: String,
         subtitle: String? = nil,
         spacing: CGFloat = Spacing.md,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .sectionCard()
    }
}

/// Standard left-aligned header bar for sheets/windows.
struct SheetHeader: View {
    let title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(AppColor.controlBackground)
    }
}

/// Consistent empty-state placeholder: icon + title + optional message + optional action.
struct EmptyStateView<Action: View>: View {
    let icon: String
    let title: String
    var message: String?
    @ViewBuilder var action: () -> Action

    init(icon: String,
         title: String,
         message: String? = nil,
         @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}
