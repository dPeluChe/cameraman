//
//  ProjectLibrary.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

/// ProjectLibrary provides a high-level API for managing projects
public actor ProjectLibrary {
    /// Project store for persistence
    private let store: ProjectStore

    /// Initialize a new ProjectLibrary
    /// - Parameter store: ProjectStore to use (defaults to shared)
    public init(store: ProjectStore = ProjectStore()) {
        self.store = store
    }

    /// List all projects with optional filtering and sorting
    /// - Parameters:
    ///   - filter: Optional filter to apply
    ///   - sort: Sort order (default: by updated date, newest first)
    ///   - offset: Pagination offset (default: 0)
    ///   - limit: Maximum number of results (default: no limit)
    /// - Returns: Array of project summaries
    public func listProjects(
        filter: ProjectFilter? = nil,
        sort: SortOption = .updatedAtDescending,
        offset: Int = 0,
        limit: Int? = nil
    ) async throws -> [ProjectSummary] {
        var projects = try await store.listProjects()

        // Apply filter
        if let filter = filter {
            projects = applyFilter(projects: projects, filter: filter)
        }

        // Apply sorting
        projects = sortProjects(projects: projects, sort: sort)

        // Apply pagination
        if offset > 0 || limit != nil {
            let start = offset
            let end = limit != nil ? offset + limit! : projects.count
            let safeEnd = min(end, projects.count)
            guard start < projects.count else {
                return []
            }
            projects = Array(projects[start..<safeEnd])
        }

        return projects
    }

    /// Count total projects matching a filter (ignores pagination)
    /// - Parameter filter: Optional filter to apply
    /// - Returns: Total count of matching projects
    public func countProjects(filter: ProjectFilter? = nil) async throws -> Int {
        let projects = try await store.listProjects()

        if let filter = filter {
            return applyFilter(projects: projects, filter: filter).count
        }

        return projects.count
    }

    /// Get all unique tags across all projects
    /// - Returns: Array of unique tags, sorted alphabetically
    public func getAllTags() async throws -> [String] {
        let projects = try await store.listProjects()
        let allTags = projects.flatMap { $0.tags }
        return Array(Set(allTags)).sorted()
    }

    /// Resolve the on-disk directory for a project.
    /// - Parameter projectId: Project identifier
    /// - Returns: Project directory URL
    public func getProjectDirectory(projectId: ProjectId) async throws -> URL {
        try await store.projectDirectoryURL(for: projectId)
    }

    /// Search projects by text with advanced options
    /// - Parameters:
    ///   - searchText: Search query
    ///   - searchFields: Which fields to search (default: name and tags)
    ///   - matchAllTerms: If true, all terms must match; if false, any term can match (default: false)
    ///   - sort: Sort order for results
    /// - Returns: Array of matching project summaries
    public func searchProjects(
        searchText: String,
        searchFields: SearchFields = [.name, .tags],
        matchAllTerms: Bool = false,
        sort: SortOption = .updatedAtDescending
    ) async throws -> [ProjectSummary] {
        let projects = try await store.listProjects()

        guard !searchText.isEmpty else {
            return sortProjects(projects: projects, sort: sort)
        }

        // Split search text into terms
        let terms = searchText.split(separator: " ").map { String($0).lowercased() }

        let filtered = projects.filter { project in
            let matches: [Bool] = terms.map { term in
                var matched = false

                if searchFields.contains(.name) && project.name.lowercased().contains(term) {
                    matched = true
                }

                if searchFields.contains(.tags) && project.tags.contains(where: { $0.lowercased().contains(term) }) {
                    matched = true
                }

                return matched
            }

            return matchAllTerms ? matches.allSatisfy { $0 } : matches.contains { $0 }
        }

        return sortProjects(projects: filtered, sort: sort)
    }

    // MARK: - Private Helper Methods

    /// Apply filter to project list
    private func applyFilter(projects: [ProjectSummary], filter: ProjectFilter) -> [ProjectSummary] {
        var filtered = projects

        // Apply text search
        if !filter.searchText.isEmpty {
            let terms = filter.searchText.split(separator: " ").map { String($0).lowercased() }
            filtered = filtered.filter { project in
                // Check if all terms match (in name or tags)
                return terms.allSatisfy { term in
                    project.name.lowercased().contains(term) ||
                    project.tags.contains { $0.lowercased().contains(term) }
                }
            }
        }

        // Apply tag filtering
        if !filter.tags.isEmpty {
            switch filter.tagMatchMode {
            case .all:
                // All specified tags must be present
                filtered = filtered.filter { project in
                    filter.tags.allSatisfy { project.tags.contains($0) }
                }
            case .any:
                // At least one of the specified tags must be present
                filtered = filtered.filter { project in
                    filter.tags.contains { project.tags.contains($0) }
                }
            }

            // Apply excluded tags
            if !filter.excludedTags.isEmpty {
                filtered = filtered.filter { project in
                    !filter.excludedTags.contains { project.tags.contains($0) }
                }
            }
        }

        // Apply date range filter
        if let dateRange = filter.dateRange {
            filtered = filtered.filter { project in
                if let startDate = dateRange.startDate {
                    if project.updatedAt < startDate {
                        return false
                    }
                }
                if let endDate = dateRange.endDate {
                    if project.updatedAt > endDate {
                        return false
                    }
                }
                return true
            }
        }

        // Apply duration range filter
        if let durationRange = filter.durationRange {
            filtered = filtered.filter { project in
                project.duration >= durationRange.minDuration &&
                project.duration <= durationRange.maxDuration
            }
        }

        return filtered
    }

    /// Sort projects by specified option
    private func sortProjects(projects: [ProjectSummary], sort: SortOption) -> [ProjectSummary] {
        switch sort {
        case .nameAscending:
            return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .createdAtAscending:
            return projects.sorted { $0.createdAt < $1.createdAt }
        case .createdAtDescending:
            return projects.sorted { $0.createdAt > $1.createdAt }
        case .updatedAtAscending:
            return projects.sorted { $0.updatedAt < $1.updatedAt }
        case .updatedAtDescending:
            return projects.sorted { $0.updatedAt > $1.updatedAt }
        case .durationAscending:
            return projects.sorted { $0.duration < $1.duration }
        case .durationDescending:
            return projects.sorted { $0.duration > $1.duration }
        case .tagsAscending:
            return projects.sorted { lhs, rhs in
                let lhsTags = lhs.tags.joined(separator: ", ").lowercased()
                let rhsTags = rhs.tags.joined(separator: ", ").lowercased()
                return lhsTags.localizedCaseInsensitiveCompare(rhsTags) == .orderedAscending
            }
        case .tagsDescending:
            return projects.sorted { lhs, rhs in
                let lhsTags = lhs.tags.joined(separator: ", ").lowercased()
                let rhsTags = rhs.tags.joined(separator: ", ").lowercased()
                return lhsTags.localizedCaseInsensitiveCompare(rhsTags) == .orderedDescending
            }
        }
    }

    /// Rename a project
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - newName: New name
    public func renameProject(projectId: ProjectId, to newName: String) async throws {
        try await store.renameProject(projectId: projectId, to: newName)
    }

    /// Set tags for a project
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - tags: New tags (replaces existing tags)
    public func setTags(projectId: ProjectId, tags: [String]) async throws {
        try await store.setTags(projectId: projectId, tags: tags)
    }

    /// Add a tag to a project
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - tag: Tag to add
    public func addTag(projectId: ProjectId, tag: String) async throws {
        let project = try await store.loadProject(projectId: projectId)
        var tags = project.tags
        if !tags.contains(tag) {
            tags.append(tag)
            try await store.setTags(projectId: projectId, tags: tags)
        }
    }

    /// Remove a tag from a project
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - tag: Tag to remove
    public func removeTag(projectId: ProjectId, tag: String) async throws {
        let project = try await store.loadProject(projectId: projectId)
        let tags = project.tags.filter { $0 != tag }
        try await store.setTags(projectId: projectId, tags: tags)
    }

    /// Delete a project
    /// - Parameter projectId: Project ID to delete
    public func deleteProject(projectId: ProjectId) async throws {
        try await store.deleteProject(projectId: projectId)
    }

    public func createProject(from recordingResult: Recorder.RecordingResult, name: String? = nil, tags: [String]? = nil) async throws -> ProjectId {
        try await store.createProject(from: recordingResult, name: name, tags: tags)
    }

    /// Add a new take to an existing project
    /// - Parameters:
    ///   - projectId: Project to add take to
    ///   - recordingResult: Result from recording session
    /// - Returns: The added Take
    public func addTake(projectId: ProjectId, recordingResult: Recorder.RecordingResult) async throws -> Project.Take {
        try await store.addTake(projectId: projectId, recordingResult: recordingResult)
    }

    /// Get a project by ID
    /// - Parameter projectId: Project ID
    /// - Returns: The project
    public func getProject(projectId: ProjectId) async throws -> Project {
        return try await store.loadProject(projectId: projectId)
    }

    /// Update a project
    /// - Parameter project: Project to update
    public func updateProject(_ project: Project) async throws {
        try await store.saveProject(project)
    }

    /// Get the ExportEngine for exporting projects
    /// - Returns: ExportEngine instance
    public func getExportEngine() async throws -> ExportEngine {
        let jobQueue = JobQueue()
        return ExportEngine(jobQueue: jobQueue, projectStore: store)
    }

    /// Create an AIService instance for the project library
    /// - Returns: Configured AIService
    public func getAIService() async throws -> AIService {
        let jobQueue = JobQueue()
        let service = AIService(jobQueue: jobQueue, projectStore: store)
        return service
    }

    /// Get the shared job queue for operations
    /// - Returns: JobQueue instance
    public func getJobQueue() async throws -> JobQueue {
        return JobQueue()
    }
}

/// Filter for listing projects
public struct ProjectFilter {
    /// Search text (searches in name and tags)
    public var searchText: String
    /// Tags to filter by
    public var tags: [String]
    /// How to match multiple tags (default: all must be present)
    public var tagMatchMode: TagMatchMode
    /// Tags to exclude (projects with these tags will be filtered out)
    public var excludedTags: [String]
    /// Date range filter (based on updatedAt)
    public var dateRange: DateRange?
    /// Duration range filter
    public var durationRange: DurationRange?

    public init(
        searchText: String = "",
        tags: [String] = [],
        tagMatchMode: TagMatchMode = .all,
        excludedTags: [String] = [],
        dateRange: DateRange? = nil,
        durationRange: DurationRange? = nil
    ) {
        self.searchText = searchText
        self.tags = tags
        self.tagMatchMode = tagMatchMode
        self.excludedTags = excludedTags
        self.dateRange = dateRange
        self.durationRange = durationRange
    }

    /// Tag matching mode
    public enum TagMatchMode {
        /// All specified tags must be present
        case all
        /// At least one of the specified tags must be present
        case any
    }

    /// Date range filter
    public struct DateRange {
        public let startDate: Date?
        public let endDate: Date?

        public init(startDate: Date? = nil, endDate: Date? = nil) {
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    /// Duration range filter (in seconds)
    public struct DurationRange {
        public let minDuration: TimeInterval
        public let maxDuration: TimeInterval

        public init(minDuration: TimeInterval = 0, maxDuration: TimeInterval = .infinity) {
            self.minDuration = minDuration
            self.maxDuration = maxDuration
        }
    }
}

/// Sort options for project listings
public enum SortOption {
    case nameAscending
    case nameDescending
    case createdAtAscending
    case createdAtDescending
    case updatedAtAscending
    case updatedAtDescending
    case durationAscending
    case durationDescending
    case tagsAscending
    case tagsDescending
}

/// Search fields for text search
public struct SearchFields: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Search in project name
    public static let name = SearchFields(rawValue: 1 << 0)
    /// Search in project tags
    public static let tags = SearchFields(rawValue: 1 << 1)
}
