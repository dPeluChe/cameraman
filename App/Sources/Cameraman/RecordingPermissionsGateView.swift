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
                row(title: "Screen Recording", systemImage: "rectangle.dashed.badge.record",
                    status: viewModel.screenStatus,
                    note: "If you just enabled it in Settings, reopen the app.") {
                    Task { await viewModel.requestScreenPermission() }
                }
                row(title: "Camera", systemImage: "video",
                    status: viewModel.cameraStatus, note: nil) {
                    Task { await viewModel.requestCameraPermission() }
                }
                row(title: "Microphone", systemImage: "mic",
                    status: viewModel.micStatus, note: nil) {
                    Task { await viewModel.requestMicPermission() }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

            Button {
                Task { await viewModel.refreshPermissions() }
            } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.link)

            Text("Continue unlocks once all three are granted.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
