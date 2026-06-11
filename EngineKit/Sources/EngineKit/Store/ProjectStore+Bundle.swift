//
//  ProjectStore+Bundle.swift
//  EngineKit
//
//  Export a project as a portable folder bundle (essentials only) and import
//  one back under a fresh id — for sharing projects between machines.
//

import Foundation

extension ProjectStore {

    /// Folders/files that can be regenerated and are excluded from bundles.
    private static let regenerable: Set<String> = ["cache", "proxies", "renders", "transcript"]

    /// Copy the project's essential contents (project.json, sources, telemetry,
    /// imported assets, thumbnail) into `destinationFolder/<Name>.cameramanproject`.
    /// - Returns: The created bundle URL.
    public func exportProjectBundle(projectId: ProjectId, to destinationFolder: URL) async throws -> URL {
        let project = try await loadProject(projectId: projectId)
        let projectDir = try projectDirectoryURL(for: projectId)

        let safeName = project.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let bundleURL = destinationFolder.appendingPathComponent("\(safeName).cameramanproject", isDirectory: true)

        guard !fileManager.fileExists(atPath: bundleURL.path) else {
            throw EngineKitError.invalidConfiguration("\(bundleURL.lastPathComponent) already exists at the destination")
        }

        try copyTree(from: projectDir, to: bundleURL, skipping: Self.regenerable)
        logger.info("Exported project bundle to \(bundleURL.path)")
        return bundleURL
    }

    /// Import a bundle (or any copied project folder) as a NEW project: contents
    /// are copied into the store and the project gets a fresh id so it can live
    /// next to the original.
    public func importProjectBundle(from bundleURL: URL) async throws -> ProjectId {
        let projectFile = bundleURL.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: projectFile.path) else {
            throw EngineKitError.invalidConfiguration("Not a Cameraman project: missing project.json")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original: Project
        do {
            original = try decoder.decode(Project.self, from: try Data(contentsOf: projectFile))
        } catch {
            throw EngineKitError.invalidConfiguration("Not a Cameraman project: unreadable project.json (\(error.localizedDescription))")
        }

        let newId = ProjectId()
        let destDir = baseDirectory.appendingPathComponent(newId.uuidString, isDirectory: true)
        do {
            try copyTree(from: bundleURL, to: destDir)
            try createProjectDirectoryStructure(at: destDir)  // restore regenerable dirs
        } catch {
            try? fileManager.removeItem(at: destDir)
            throw error
        }

        let imported = original.withNewIdentity(projectId: newId)
        try await saveProject(imported)
        logger.info("Imported project bundle as \(newId.uuidString)")
        return newId
    }
}
