//
//  AboutPreferencesView.swift
//  App
//
//  About tab inside Settings: app icon, version, repo, and donation links.
//

import SwiftUI

struct AboutPreferencesView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    var body: some View {
        VStack(spacing: 24) {
            // Icon + identity
            VStack(spacing: 8) {
                if let img = NSImage(named: "AppIcon") {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.accentColor)
                }
                Text("Cameraman")
                    .font(.title2.bold())
                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Open source screen recording for macOS")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // Links
            VStack(spacing: 10) {
                linkRow(icon: "chevron.left.forwardslash.chevron.right",
                        label: "Source Code",
                        url: AppLinks.repo)
                linkRow(icon: "ladybug",
                        label: "Report a Bug",
                        url: AppLinks.issues)
                linkRow(icon: "envelope",
                        label: "Contact Support",
                        url: AppLinks.contact)
            }

            Divider()

            // Donations
            VStack(spacing: 6) {
                Text("Support the project")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    donateButton(label: "GitHub Sponsors ♥", url: AppLinks.sponsors, color: .pink)
                    donateButton(label: "PayPal", url: AppLinks.paypal, color: .blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func linkRow(icon: String, label: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 320)
    }

    private func donateButton(label: String, url: URL, color: Color) -> some View {
        Button(label) { NSWorkspace.shared.open(url) }
            .buttonStyle(.bordered)
            .tint(color)
            .controlSize(.small)
    }
}
