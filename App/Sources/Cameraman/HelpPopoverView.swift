//
//  HelpPopoverView.swift
//  App
//
//  Quick-access popover from the toolbar ? button: version, links, donations.
//

import SwiftUI

struct HelpPopoverView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                if let img = NSImage(named: "AppIcon") {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cameraman")
                        .font(.headline)
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Links
            VStack(alignment: .leading, spacing: 8) {
                popoverLink("Cameraman Help", icon: "book", url: AppLinks.help)
                popoverLink("View on GitHub", icon: "chevron.left.forwardslash.chevron.right", url: AppLinks.repo)
                popoverLink("Report a Bug", icon: "ladybug", url: AppLinks.issues)
                popoverLink("Contact Support", icon: "envelope", url: AppLinks.contact)
            }

            Divider()

            // Donations
            VStack(alignment: .leading, spacing: 6) {
                Text("Support the project")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    donateButton("Sponsors ♥", url: AppLinks.sponsors, color: .pink)
                    donateButton("PayPal", url: AppLinks.paypal, color: .blue)
                }
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    private func popoverLink(_ label: String, icon: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 14)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func donateButton(_ label: String, url: URL, color: Color) -> some View {
        Button(label) { NSWorkspace.shared.open(url) }
            .buttonStyle(.bordered)
            .tint(color)
            .controlSize(.mini)
    }
}
