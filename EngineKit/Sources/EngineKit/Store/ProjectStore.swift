//
//  ProjectStore.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import CryptoKit
import Foundation
import os.log

/// ProjectStore manages project persistence on disk
public actor ProjectStore {

    /// Compute SHA256 hex digest for a file using streaming (constant memory). Returns "unknown" on error.
    func sha256(of url: URL) -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else { return "unknown" }
        defer { try? file.close() }

        var hasher = SHA256()
        let bufferSize = 65536 // 64KB chunks
        while autoreleasepool(invoking: {
            let chunk = file.readData(ofLength: bufferSize)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Get file size in bytes. Returns 0 on error.
    func fileSize(of url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }
    /// Base directory for all projects
    let baseDirectory: URL
    /// File manager for disk operations
    let fileManager: FileManager
    /// Structured logging
    let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "ProjectStore")

    /// Current schema version
    let currentSchemaVersion = 2

    /// Initialize a new ProjectStore
    /// - Parameter baseDirectory: Base directory for projects (defaults to Application Support)
    public init(baseDirectory: URL? = nil) {
        self.fileManager = FileManager.default

        if let baseDirectory = baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            // Default to Application Support/ProjectStudio/Projects
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("ProjectStudio/Projects", isDirectory: true)
        }

        // Create base directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
            logger.debug("ProjectStore initialized with base directory: \(self.baseDirectory.path)")
        } catch {
            logger.error("Failed to create base directory: \(error.localizedDescription)")
            reportError(error, context: "ProjectStore.init")
        }
    }

    // MARK: - Project CRUD

    /// Load a project by ID
    /// - Parameter projectId: Project ID to load
    /// - Returns: The loaded Project
    /// - Throws: EngineKitError.projectNotFound if project doesn't exist
    public func loadProject(projectId: ProjectId) async throws -> Project {
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
        let projectFile = projectDirectory.appendingPathComponent("project.json")

        guard fileManager.fileExists(atPath: projectFile.path) else {
            throw EngineKitError.projectNotFound(projectId)
        }

        let data = try Data(contentsOf: projectFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(Project.self, from: data)

        // Check if migration is needed
        if project.schemaVersion < currentSchemaVersion {
            return try await migrateProject(project, to: currentSchemaVersion)
        }

        return project
    }

    /// Resolve the on-disk directory for a project.
    /// - Parameter projectId: Project identifier
    /// - Returns: Project directory URL
    /// - Throws: EngineKitError.projectNotFound if the directory is missing
    public func projectDirectoryURL(for projectId: ProjectId) throws -> URL {
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: projectDirectory.path) else {
            throw EngineKitError.projectNotFound(projectId)
        }
        return projectDirectory
    }

    /// Save a project
    /// - Parameter project: Project to save
    /// - Throws: EngineKitError if save fails
    public func saveProject(_ project: Project) async throws {
        var projectToSave = project
        projectToSave.updatedAt = Date()

        let projectDirectory = baseDirectory.appendingPathComponent(project.projectId.uuidString, isDirectory: true)
        let projectFile = projectDirectory.appendingPathComponent("project.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(projectToSave)
        try data.write(to: projectFile)
    }

    /// Delete a project
    /// - Parameter projectId: Project ID to delete
    /// - Throws: EngineKitError if deletion fails
    public func deleteProject(projectId: ProjectId) async throws {
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)

        guard fileManager.fileExists(atPath: projectDirectory.path) else {
            throw EngineKitError.projectNotFound(projectId)
        }

        try fileManager.removeItem(at: projectDirectory)
    }

    /// Duplicate a project (deep copy of all files)
    /// - Parameter projectId: Source project ID
    /// - Returns: New project ID of the duplicate
    public func duplicateProject(projectId: ProjectId) async throws -> ProjectId {
        let sourceDir = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceDir.path) else {
            throw EngineKitError.projectNotFound(projectId)
        }

        let newProjectId = ProjectId()
        let destDir = baseDirectory.appendingPathComponent(newProjectId.uuidString, isDirectory: true)

        try fileManager.copyItem(at: sourceDir, to: destDir)

        // Update project metadata with new ID and name
        let projectFile = destDir.appendingPathComponent("project.json")
        let data = try Data(contentsOf: projectFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var project = try decoder.decode(Project.self, from: data)

        project = project.withNewIdentity(
            projectId: newProjectId,
            name: "\(project.name) (Copy)",
            resetCreatedAt: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: projectFile)

        return newProjectId
    }

    /// Rename a project
    /// - Parameters:
    ///   - projectId: Project ID to rename
    ///   - newName: New name
    /// - Throws: EngineKitError if rename fails
    public func renameProject(projectId: ProjectId, to newName: String) async throws {
        var project = try await loadProject(projectId: projectId)
        project.name = newName
        try await saveProject(project)
    }

    /// Set tags for a project
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - tags: New tags
    /// - Throws: EngineKitError if operation fails
    public func setTags(projectId: ProjectId, tags: [String]) async throws {
        var project = try await loadProject(projectId: projectId)
        project.tags = tags
        try await saveProject(project)
    }

    // MARK: - Project Listing

    /// List all projects sorted by update date
    /// - Returns: Array of ProjectSummary
    /// Cache of project summaries keyed by project.json URL, with file modification date for invalidation
    private var summaryCache: [URL: (modDate: Date, summary: ProjectSummary)] = [:]

    public func listProjects() async throws -> [ProjectSummary] {
        let directories = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var summaries: [ProjectSummary] = []
        var seenURLs: Set<URL> = []

        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }

            let projectFile = directory.appendingPathComponent("project.json")

            guard fileManager.fileExists(atPath: projectFile.path) else { continue }
            seenURLs.insert(projectFile)

            // Check file modification date to skip unchanged projects
            let attrs = try? fileManager.attributesOfItem(atPath: projectFile.path)
            let modDate = attrs?[.modificationDate] as? Date

            if let modDate, let cached = summaryCache[projectFile], cached.modDate == modDate {
                summaries.append(cached.summary)
                continue
            }

            do {
                let data = try Data(contentsOf: projectFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let project = try decoder.decode(Project.self, from: data)

                let thumbPath = directory.appendingPathComponent("thumbnail.jpg")
                let thumbnailPath = fileManager.fileExists(atPath: thumbPath.path) ? thumbPath.path : nil

                let summary = ProjectSummary(
                    projectId: project.projectId,
                    name: project.name,
                    createdAt: project.createdAt,
                    updatedAt: project.updatedAt,
                    tags: project.tags,
                    duration: project.timeline.duration,
                    thumbnailPath: thumbnailPath
                )

                summaries.append(summary)
                if let modDate {
                    summaryCache[projectFile] = (modDate: modDate, summary: summary)
                }
            } catch {
                continue
            }
        }

        // Evict cache entries for deleted projects
        for key in summaryCache.keys where !seenURLs.contains(key) {
            summaryCache.removeValue(forKey: key)
        }

        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

}
