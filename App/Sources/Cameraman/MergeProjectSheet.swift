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
    @State private var selectedId: ProjectId?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Merge “\(source.name)” with…")
                    .font(.headline)
                Text("Creates a new project: “\(source.name)” first, then the selected project. Originals are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List(candidates, selection: $selectedId) { project in
                HStack {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(ProjectSummaryFormatting.duration(project.duration))
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
                    if let selected = candidates.first(where: { $0.projectId == selectedId }) {
                        onMerge(selected)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedId == nil)
            }
        }
        .padding(20)
        .frame(width: 380, height: 330)
    }
}
