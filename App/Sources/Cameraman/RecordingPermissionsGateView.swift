//
//  RecordingPermissionsGateView.swift
//  App
//
//  Step 0 of the recording flow: require Screen Recording + Camera + Microphone
//  before the user can pick a source, so permissions are handled up-front instead
//  of interrupting (or failing) mid-recording.
//

import SwiftUI
import EngineKit

struct RecordingPermissionsGateView: View {
    @ObservedObject var viewModel: RecordingControlViewModel

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                Text("Permissions needed")
                    .font(.headline)
                Text("Cameraman needs these to record. Grant all to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            VStack(spacing: 8) {
                // Camera & mic first (instant, no relaunch); Screen Recording last since it
                // needs a one-time reopen — grant it at the end.
                row(title: "Camera", systemImage: "video",
                    status: viewModel.cameraStatus,
                    note: "Settings → Camera, enable “\(appName)”. If macOS asks, choose Later — no reopen needed.") {
                    Task { await viewModel.requestCameraPermission() }
                }
                row(title: "Microphone", systemImage: "mic",
                    status: viewModel.micStatus,
                    note: "Settings → Microphone, enable “\(appName)”. If macOS asks, choose Later — no reopen needed.") {
                    Task { await viewModel.requestMicPermission() }
                }
                row(title: "Screen Recording", systemImage: "rectangle.dashed.badge.record",
                    status: viewModel.screenStatus,
                    note: "Settings → Screen Recording, enable “\(appName)”, then Quit & Reopen (last step).") {
                    Task { await viewModel.requestScreenPermission() }
                }
            }
            .sectionCard(padding: Spacing.md)

            if !viewModel.allRequiredPermissionsGranted {
                Button {
                    Task { await viewModel.requestAllPermissions() }
                } label: {
                    Text("Grant Permissions")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.refreshPermissions() }
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.link)

                Button {
                    relaunchApp()
                } label: {
                    Label("Quit & Reopen", systemImage: "arrow.triangle.2.circlepath").font(.caption)
                }
                .buttonStyle(.link)
            }

            Text("Continue unlocks once all three are granted. Screen Recording needs a reopen.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    /// App's user-facing name (e.g. "Cameraman" or "Cameraman (Debug)") so the
    /// instructions name the exact entry the user must find in System Settings.
    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Cameraman"
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder
    private func row(title: String, systemImage: String,
                     status: PermissionManager.PermissionStatus,
                     note: String?,
                     grant: @escaping () -> Void) -> some View {
        let ok = status == .authorized
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(ok ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                if !ok, let note {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if ok {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(status == .denied ? "Open Settings" : "Grant", action: grant)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
