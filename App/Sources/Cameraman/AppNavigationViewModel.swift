//
//  AppNavigationViewModel.swift
//  App
//
//  Extracted from AppNavigation.swift
//  View model, enums, and notification names for app navigation
//

import Combine
import SwiftUI
import EngineKit

extension Notification.Name {
    static let openProject = Notification.Name("openProject")
}

enum AppNavigationItem: Hashable {
    case recording
    case project(ProjectId)
}

enum ProjectLibraryLayout: String, CaseIterable {
    case list
    case grid
}

enum ProjectSortOption: String, CaseIterable {
    case dateUpdated = "Date Updated"
    case name = "Name"
    case duration = "Duration"
    case dateCreated = "Date Created"
}

@MainActor
final class AppNavigationViewModel: ObservableObject {
    @Published private(set) var projects: [ProjectSummary] = []
    @Published var selectedItem: AppNavigationItem = .recording
    @Published private(set) var loadErrorMessage: String?
    @Published var libraryLayout: ProjectLibraryLayout = .list
    @Published var searchText: String = ""
    @Published var selectedTagFilter: String? = nil
    @Published var sortOption: ProjectSortOption = .dateUpdated
    @Published var sortDirectionAscending: Bool = false

    private let library: ProjectLibrary
    private var lastLoadTime: Date?

    nonisolated init(library: ProjectLibrary = ProjectLibrary.shared) {
        self.library = library
    }

    var filteredProjects: [ProjectSummary] {
        var result = projects

        if !searchText.isEmpty {
            let lowercaseSearch = searchText.lowercased()
            result = result.filter { project in
                project.name.lowercased().contains(lowercaseSearch)
            }
        }

        if let tagFilter = selectedTagFilter {
            result = result.filter { project in
                project.tags.contains(tagFilter)
            }
        }

        result.sort { lhs, rhs in
            switch sortOption {
            case .dateUpdated:
                let comparison = lhs.updatedAt.compare(rhs.updatedAt)
                if sortDirectionAscending {
                    return comparison == .orderedAscending
                } else {
                    return comparison == .orderedDescending
                }
            case .dateCreated:
                let comparison = lhs.createdAt.compare(rhs.createdAt)
                if sortDirectionAscending {
                    return comparison == .orderedAscending
                } else {
                    return comparison == .orderedDescending
                }
            case .name:
                let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if sortDirectionAscending {
                    return comparison == .orderedAscending
                } else {
                    return comparison == .orderedDescending
                }
            case .duration:
                if sortDirectionAscending {
                    return lhs.duration < rhs.duration
                } else {
                    return lhs.duration > rhs.duration
                }
            }
        }

        return result
    }

    var allTags: [String] {
        var tags = Set<String>()
        for project in projects {
            for tag in project.tags {
                tags.insert(tag)
            }
        }
        return Array(tags).sorted()
    }

    func loadProjects() async {
        // Debounce: skip if called within 500ms of last load
        let now = Date()
        if let last = lastLoadTime, now.timeIntervalSince(last) < 0.5 {
            return
        }
        lastLoadTime = now

        do {
            let loadedProjects = try await library.listProjects()
            projects = loadedProjects
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func project(for projectId: ProjectId) -> ProjectSummary? {
        projects.first { $0.projectId == projectId }
    }

    func renameProject(projectId: ProjectId, to newName: String) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            loadErrorMessage = "Project name can't be empty."
            return
        }

        do {
            try await library.renameProject(projectId: projectId, to: trimmedName)
            await loadProjects()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func deleteProject(projectId: ProjectId) async {
        do {
            try await library.deleteProject(projectId: projectId)
            await loadProjects()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func duplicateProject(projectId: ProjectId) async {
        do {
            let newId = try await library.duplicateProject(projectId: projectId)
            await loadProjects()
            selectedItem = .project(newId)
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    /// Merge two projects into a new one (second appended after first) and select it.
    func mergeProjects(_ firstId: ProjectId, with secondId: ProjectId) async {
        do {
            let newId = try await library.mergeProjects(firstId, secondId)
            await loadProjects()
            selectedItem = .project(newId)
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func setTags(projectId: ProjectId, tags: [String]) async {
        let cleanedTags = Self.normalizeTags(tags)
        do {
            try await library.setTags(projectId: projectId, tags: cleanedTags)
            await loadProjects()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    static func parseTagsInput(_ input: String) -> [String] {
        let tokens = input.split(separator: ",")
        return normalizeTags(tokens.map { String($0) })
    }

    private static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }

    func clearError() {
        loadErrorMessage = nil
    }

    func toggleLibraryLayout() {
        libraryLayout = libraryLayout == .list ? .grid : .list
    }

    func setTagFilter(_ tag: String?) {
        selectedTagFilter = tag
    }

    func clearFilters() {
        searchText = ""
        selectedTagFilter = nil
    }

    func setSortOption(_ option: ProjectSortOption) {
        sortOption = option
    }

    func toggleSortDirection() {
        sortDirectionAscending.toggle()
    }
}
