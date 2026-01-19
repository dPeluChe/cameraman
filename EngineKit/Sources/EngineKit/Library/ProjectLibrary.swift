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

    /// List all projects
    /// - Parameter filter: Optional filter to apply
    /// - Returns: Array of project summaries
    public func listProjects(filter: ProjectFilter? = nil) async throws -> [ProjectSummary] {
        var projects = try await store.listProjects()

        if let filter = filter {
            if !filter.searchText.isEmpty {
                let searchTerm = filter.searchText.lowercased()
                projects = projects.filter { project in
                    project.name.lowercased().contains(searchTerm) ||
                    project.tags.contains { $0.lowercased().contains(searchTerm) }
                }
            }

            if !filter.tags.isEmpty {
                projects = projects.filter { project in
                    filter.tags.allSatisfy { project.tags.contains($0) }
                }
            }
        }

        return projects
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
}

/// Filter for listing projects
public struct ProjectFilter {
    /// Search text (searches in name and tags)
    public var searchText: String
    /// Tags to filter by (all must be present)
    public var tags: [String]

    public init(searchText: String = "", tags: [String] = []) {
        self.searchText = searchText
        self.tags = tags
    }
}
