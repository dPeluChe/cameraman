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


// MARK: - Project Filter Controls

/// Search field + sort controls + tag filter chips for the projects sidebar.
/// Extracted from `AppNavigation.sidebar` so the navigation file stays inside
/// the size budget and the controls use the shared design tokens.
struct ProjectFilterControls: View {
    @ObservedObject var viewModel: AppNavigationViewModel

    var body: some View {
        VStack(spacing: Spacing.sm) {
            searchField
            sortControls
            if !viewModel.allTags.isEmpty {
                tagFilter
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)
                .lineLimit(1)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(AppColor.inset)
        .cornerRadius(Radius.medium)
    }

    private var sortControls: some View {
        HStack(spacing: Spacing.sm) {
            Menu {
                ForEach(ProjectSortOption.allCases, id: \.self) { option in
                    Button {
                        viewModel.setSortOption(option)
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if viewModel.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                    Text(viewModel.sortOption.rawValue)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(AppColor.inset)
                .cornerRadius(Radius.small)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                viewModel.toggleSortDirection()
            } label: {
                Image(systemName: viewModel.sortDirectionAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 12))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(AppColor.inset)
                    .cornerRadius(Radius.small)
            }
            .buttonStyle(.plain)

            Spacer()

            if !viewModel.searchText.isEmpty || viewModel.selectedTagFilter != nil {
                Button("Clear") {
                    viewModel.clearFilters()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
            }
        }
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TagFilterButton(
                    title: "All",
                    isSelected: viewModel.selectedTagFilter == nil
                ) {
                    viewModel.setTagFilter(nil)
                }

                ForEach(viewModel.allTags, id: \.self) { tag in
                    TagFilterButton(
                        title: tag,
                        isSelected: viewModel.selectedTagFilter == tag
                    ) {
                        viewModel.setTagFilter(tag)
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
    }
}
