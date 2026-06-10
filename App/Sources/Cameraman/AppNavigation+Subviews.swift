//
//  AppNavigation+Subviews.swift
//  App
//
//  Extracted from AppNavigation.swift
//  Supporting subviews for project library navigation
//

import SwiftUI
import EngineKit

// MARK: - Project Summary Row

struct ProjectSummaryRow: View {
    let project: ProjectSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProjectThumbnailView(thumbnailPath: project.thumbnailPath)
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(formattedUpdatedAt) • \(formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !project.tags.isEmpty {
                    Text(project.tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedUpdatedAt: String {
        ProjectSummaryFormatting.dateFormatter.string(from: project.updatedAt)
    }

    private var formattedDuration: String {
        ProjectSummaryFormatting.duration(project.duration)
    }

    private static let dateFormatter = ProjectSummaryFormatting.dateFormatter
}

// MARK: - Project Grid View

struct ProjectGridView<ContextMenu: View>: View {
    let projects: [ProjectSummary]
    let selectedItem: AppNavigationItem
    let onSelect: (ProjectId) -> Void
    let contextMenu: (ProjectSummary) -> ContextMenu

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(projects) { project in
                Button {
                    onSelect(project.projectId)
                } label: {
                    ProjectSummaryCard(
                        project: project,
                        isSelected: isSelected(project.projectId)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    contextMenu(project)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func isSelected(_ projectId: ProjectId) -> Bool {
        if case let .project(selectedId) = selectedItem {
            return selectedId == projectId
        }
        return false
    }
}

// MARK: - Project Summary Card

struct ProjectSummaryCard: View {
    let project: ProjectSummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProjectThumbnailView(thumbnailPath: project.thumbnailPath)
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(project.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text("\(formattedUpdatedAt) • \(formattedDuration)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !project.tags.isEmpty {
                Text(project.tags.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var formattedUpdatedAt: String {
        ProjectSummaryFormatting.dateFormatter.string(from: project.updatedAt)
    }

    private var formattedDuration: String {
        ProjectSummaryFormatting.duration(project.duration)
    }
}

// MARK: - Project Summary Formatting

enum ProjectSummaryFormatting {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func duration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Tag Filter Button

struct TagFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08)
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
