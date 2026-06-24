//
//  ContactSupportView.swift
//  App
//
//  Contact Support window: shows the support email + links and lets the user
//  choose an action, instead of silently launching the mail client.
//

import SwiftUI
import AppKit

struct ContactSupportView: View {
    private let supportEmail = "support@dpeluche.dev"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            IconHeader(icon: "lifepreserver",
                       title: "Contact Support",
                       subtitle: "We're happy to help with Cameraman.",
                       tint: .blue)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                emailRow
                Divider()
                linkRow(icon: "ladybug", title: "Report a Bug",
                        subtitle: "Includes diagnostics (recommended)") {
                    DiagnosticsWindowController.shared.show()
                }
                linkRow(icon: "book", title: "Help & Documentation", subtitle: nil) {
                    NSWorkspace.shared.open(AppLinks.help)
                }
                linkRow(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub", subtitle: nil) {
                    NSWorkspace.shared.open(AppLinks.repo)
                }
            }
            .sectionCard()

            Text("“Compose Email” opens your default mail app with the address filled in.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xl)
        .frame(width: 440)
    }

    private var emailRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope").frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Email support").font(.system(size: 13, weight: .medium))
                Text(supportEmail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                Clipboard.copy(supportEmail)
                copied = true
            }
            .controlSize(.small)
            Button("Compose Email") {
                NSWorkspace.shared.open(AppLinks.contact)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
    }

    private func linkRow(icon: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standalone window

@MainActor
final class ContactSupportWindowController {
    static let shared = ContactSupportWindowController()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: ContactSupportView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Contact Support"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
