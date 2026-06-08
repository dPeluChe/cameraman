//
//  DiagnosticsView.swift
//  App
//
//  In-app "Report a Bug" / diagnostics panel: live permission status + one-click
//  report (env + permissions + logs + crashes) with save / copy / issue / email.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import EngineKit

struct DiagnosticsView: View {
    var crashDetected: Bool = false

    @State private var permissions: [DiagnosticsService.PermissionRow] = []
    @State private var report: String = ""
    @State private var isLoading = true
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if crashDetected { crashBanner }
            permissionsSection
            Divider()
            reportSection
            Divider()
            actionsRow
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 560)
        .task { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "stethoscope")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Report a Bug").font(.headline)
                Text("Cameraman \(DiagnosticsService.appVersion) · \(DiagnosticsService.osVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var crashBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Cameraman closed unexpectedly last time. Sending this report helps us fix it.")
                .font(.caption)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions").font(.subheadline).fontWeight(.semibold)
            ForEach(permissions) { line in
                HStack(spacing: 8) {
                    Image(systemName: line.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(line.ok ? .green : .orange)
                    Text(line.label).font(.system(size: 13))
                    Spacer()
                    Text(line.status)
                        .font(.caption)
                        .foregroundStyle(line.ok ? .secondary : .orange)
                    if !line.ok {
                        Button("Open Settings") { openSettings(for: line.label) }
                            .font(.caption)
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagnostics").font(.subheadline).fontWeight(.semibold)
            ScrollView {
                Text(isLoading ? "Collecting diagnostics…" : report)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 240)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                saveReport()
            } label: {
                Label("Save .txt", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button {
                copyReport()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(isLoading)

            Spacer()

            Button {
                NSWorkspace.shared.open(issueURL())
            } label: {
                Label("Open Issue", systemImage: "ladybug")
            }

            Button {
                NSWorkspace.shared.open(emailURL())
                statusMessage = "If you saved the .txt, attach it to the email."
            } label: {
                Label("Email", systemImage: "envelope")
            }
        }
    }

    // MARK: - Load

    private func load() async {
        permissions = await DiagnosticsService.permissionLines()
        report = await DiagnosticsService.buildReport()
        isLoading = false
    }

    // MARK: - Actions

    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Cameraman-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Saved to \(url.path)"
            } catch {
                statusMessage = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        statusMessage = "Diagnostics copied to clipboard."
    }

    private func openSettings(for label: String) {
        let pane: String
        switch label {
        case "Screen Recording": pane = "Privacy_ScreenCapture"
        case "Microphone": pane = "Privacy_Microphone"
        case "Camera": pane = "Privacy_Camera"
        default: pane = "Privacy"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - URLs (short summary only — logs go in the saved file)

    private var summary: String {
        var s = "Version: \(DiagnosticsService.appVersion)\nmacOS: \(DiagnosticsService.osVersion)\n"
        s += "Model: \(DiagnosticsService.deviceModel) (\(DiagnosticsService.architecture))\n\nPermissions:\n"
        s += permissions.map { "- \($0.label): \($0.status)" }.joined(separator: "\n")
        s += "\n\n(Describe the problem here. Attach the saved Cameraman-Diagnostics.txt.)"
        return s
    }

    private func issueURL() -> URL {
        var components = URLComponents(string: "https://github.com/dPeluChe/cameraman/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: "Bug report — Cameraman \(DiagnosticsService.appVersion)"),
            URLQueryItem(name: "body", value: summary),
        ]
        return components.url ?? AppLinks.issues
    }

    private func emailURL() -> URL {
        var components = URLComponents(string: "mailto:support@dpeluche.dev")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Cameraman bug report — \(DiagnosticsService.appVersion)"),
            URLQueryItem(name: "body", value: summary),
        ]
        return components.url ?? AppLinks.contact
    }
}

// MARK: - Standalone window

@MainActor
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()
    private var window: NSWindow?

    private init() {}

    func show(crashDetected: Bool = false) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: DiagnosticsView(crashDetected: crashDetected))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 560, height: 580))
        window.title = "Report a Bug"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
