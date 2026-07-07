//
//  SyntheticCursorControlsView.swift
//  App
//
//  Toggle for the compositor-rendered synthetic cursor.
//

import SwiftUI
import EngineKit

struct SyntheticCursorControlsView: View {
    @ObservedObject var editor: ProjectEditor

    var isEnabled: Bool {
        editor.project.syntheticCursor?.enabled ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Synthetic Cursor", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    Task { await toggleEnabled(newValue) }
                }
            ))

            Text("Renders a cursor dot and click ripples directly into the video. Useful when the system cursor is hidden or you want a styled pointer.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func toggleEnabled(_ enabled: Bool) async {
        await editor.setSyntheticCursorEnabled(enabled)
    }
}
