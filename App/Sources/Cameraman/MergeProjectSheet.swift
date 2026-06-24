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
    @State private var aspectNote: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("Merge “\(source.name)” with…",
                        subtitle: "Creates a new project: “\(source.name)” first, then the selected project. Originals are kept.")

            Divider()

            VStack(alignment: .leading, spacing: Spacing.md) {
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

                if let aspectNote {
                    Label(aspectNote, systemImage: "aspectratio")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

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
            .padding(Spacing.xl)
        }
        .modalFrame(.small)
        .onChangeCompat(of: selectedId) { _ in
            updateAspectNote()
        }
    }

    /// Same aspect ratio (even at different resolutions) renders identically, so
    /// only warn when the canvases actually differ in shape — those sections get bars.
    private func updateAspectNote() {
        guard let selectedId else {
            aspectNote = nil
            return
        }
        Task {
            do {
                let base = try await ProjectLibrary.shared.getProject(projectId: source.projectId)
                let other = try await ProjectLibrary.shared.getProject(projectId: selectedId)
                let baseFormat = base.canvas.format
                let otherFormat = other.canvas.format
                let baseRatio = Double(baseFormat.w) / Double(max(1, baseFormat.h))
                let otherRatio = Double(otherFormat.w) / Double(max(1, otherFormat.h))

                await MainActor.run {
                    if abs(baseRatio - otherRatio) > 0.01 {
                        aspectNote = "Different canvas shape (\(otherFormat.aspect) vs \(baseFormat.aspect)) — those sections will be centered with bars on “\(source.name)”’s canvas."
                    } else {
                        aspectNote = nil
                    }
                }
            } catch {
                await MainActor.run { aspectNote = nil }
            }
        }
    }
}
