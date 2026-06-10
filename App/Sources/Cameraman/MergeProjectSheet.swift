//
//  MergeProjectSheet.swift
//  App
//
//  Picker for "Merge Into New Project…": choose the project whose timeline is
//  appended after the source project's. Both originals are left untouched.
//

import SwiftUI
import EngineKit

struct MergeProjectSheet: View {
    let source: ProjectSummary
    let candidates: [ProjectSummary]
    let onMerge: (ProjectSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: ProjectSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Merge “\(source.name)” with…")
                    .font(.headline)
                Text("Creates a new project: “\(source.name)” first, then the selected project. Originals are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List(candidates, selection: Binding(
                get: { selected?.projectId },
                set: { id in selected = candidates.first { $0.projectId == id } }
            )) { project in
                HStack {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(durationText(project.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(project.projectId)
            }
            .frame(minHeight: 180)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Merge") {
                    if let selected {
                        onMerge(selected)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 380, height: 330)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
