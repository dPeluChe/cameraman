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

/// Standard header bar for sheets/windows: title (+ optional subtitle) on the left,
/// optional trailing accessory (action buttons) on the right.
struct SheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String,
         subtitle: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.md)
            trailing()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(AppColor.controlBackground)
    }
}

/// Header with a leading SF Symbol, title, and optional subtitle. For titled AppKit
/// windows (Diagnostics, Contact Support) that already have a native title bar, so
/// they don't need `SheetHeader`'s full-width bar.
struct IconHeader: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color

    init(icon: String, title: String, subtitle: String? = nil, tint: Color = .accentColor) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

/// Full-width icon + title label for panel action buttons. Replaces the
/// ad-hoc `HStack { Image; Text }.frame(maxWidth: .infinity).padding(...)`
/// pattern repeated across inspector panels. Wrap in a Button and apply the
/// button style at the call site.
struct PanelActionLabel: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(title)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
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
