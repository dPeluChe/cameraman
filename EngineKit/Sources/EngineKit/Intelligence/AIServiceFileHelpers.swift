//
//  AIServiceFileHelpers.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

extension AIService {
    // MARK: - File Helpers

    func getProjectDirectory(for projectId: ProjectId) -> URL {
        if let baseDirectory = projectDirectoryOverride {
            return baseDirectory.appendingPathComponent(projectId.uuidString)
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let projectsDir = appSupport.appendingPathComponent("ProjectStudio/Projects")
        return projectsDir.appendingPathComponent(projectId.uuidString)
    }

    func getAudioPath(for project: Project) -> String? {
        // Prefer mic audio, fall back to system audio
        if let micPath = project.primarySources?.audio?.mic?.path {
            return micPath
        }
        return project.primarySources?.audio?.system?.path
    }

    func getTranscriptPath(for projectId: ProjectId) -> URL {
        let projectDir = getProjectDirectory(for: projectId)
        return projectDir.appendingPathComponent("transcript/transcript.json")
    }

    /// File holding one suggestion job's result (silence and chapters used to overwrite a shared file).
    /// Public so readers outside EngineKit, such as the MCP server, build the same name.
    public static func suggestionsFileName(jobId: JobId) -> String {
        "ai_suggestions_\(jobId.uuidString).json"
    }

    func saveSuggestions(_ suggestions: [Suggestion], for projectId: ProjectId, jobId: JobId) async {
        let projectDir = getProjectDirectory(for: projectId)
        // Latest run, kept for existing readers; the per-job file is the one that is never overwritten.
        let suggestionsPath = projectDir.appendingPathComponent("ai_suggestions.json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(suggestions)
            try data.write(to: suggestionsPath)
            try data.write(to: projectDir.appendingPathComponent(Self.suggestionsFileName(jobId: jobId)))

            await EngineKit.logging.debug(
                category: .ai,
                "Saved \(suggestions.count) suggestions to \(suggestionsPath.path)"
            )
        } catch {
            await EngineKit.logging.error(
                category: .ai,
                "Failed to save suggestions: \(error.localizedDescription)"
            )
        }
    }

    func saveGeneratedAsset(_ assetRef: AssetRef, for projectId: ProjectId) async throws -> String {
        let projectDir = getProjectDirectory(for: projectId)
        let assetsDir = projectDir.appendingPathComponent("assets")
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        // Download/copy asset to project directory
        let destinationPath = assetsDir.appendingPathComponent(assetRef.filename)
        try assetRef.data.write(to: destinationPath)

        let relativePath = "assets/\(assetRef.filename)"
        return relativePath
    }
}
