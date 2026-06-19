//
//  MCPTools+Library.swift
//  cameraman-mcp
//
//  Project management/metadata (duplicate, rename, tags, search, merge, bundle
//  import/export) and local AI suggestions (silence edits, chapters). These wrap
//  ProjectLibrary / AIService directly — no timeline mutation.
//

import Foundation
import EngineKit

extension MCPTools {

    // MARK: - Duplicate / rename / tags

    func duplicateProject(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let newId = try await ProjectLibrary.shared.duplicateProject(projectId: projectId)
        return "Duplicated project \(projectId) -> \(newId.uuidString)"
    }

    func renameProject(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let name = try args.str("name")
        try await ProjectLibrary.shared.renameProject(projectId: projectId, to: name)
        return "Renamed project \(projectId) to \"\(name)\""
    }

    func setTags(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let tags = (args["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        try await ProjectLibrary.shared.setTags(projectId: projectId, tags: tags)
        return "Set tags on \(projectId): [\(tags.joined(separator: ", "))]"
    }

    func searchProjects(_ args: [String: Any]) async throws -> String {
        let query = try args.str("query")
        let matchAll = args.optBool("matchAllTerms") ?? false
        let results = try await ProjectLibrary.shared.searchProjects(
            searchText: query, matchAllTerms: matchAll
        )
        return try jsonText(results)
    }

    // MARK: - Merge / bundles

    func mergeProjects(_ args: [String: Any]) async throws -> String {
        let firstId = try args.uuid("firstId")
        let secondId = try args.uuid("secondId")
        let name = args.optStr("name")
        let newId = try await ProjectLibrary.shared.mergeProjects(firstId, secondId, name: name)
        return "Merged \(firstId) + \(secondId) -> \(newId.uuidString)"
    }

    func exportBundle(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let folder = try args.str("destinationFolder")
        let url = try await ProjectLibrary.shared.exportProjectBundle(
            projectId: projectId,
            to: URL(fileURLWithPath: folder, isDirectory: true)
        )
        return "Exported bundle to \(url.path)"
    }

    func importBundle(_ args: [String: Any]) async throws -> String {
        let path = try args.str("bundlePath")
        let newId = try await ProjectLibrary.shared.importProjectBundle(
            from: URL(fileURLWithPath: path)
        )
        return "Imported bundle -> project \(newId.uuidString)"
    }

    // MARK: - Local AI suggestions (async jobs)

    func suggestSilenceEdits(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let ai = try await ProjectLibrary.shared.getAIService()
        let jobId = try await ai.suggestSilenceEdits(projectId: projectId)
        return try json([
            "jobId": jobId.uuidString,
            "status": "started",
            "message": "Analyzing audio for silence on-device. Poll get_job_status until success."
        ])
    }

    func suggestChapters(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let ai = try await ProjectLibrary.shared.getAIService()
        let jobId = try await ai.suggestChapters(projectId: projectId)
        return try json([
            "jobId": jobId.uuidString,
            "status": "started",
            "message": "Suggesting chapters from the transcript on-device. Poll get_job_status until success. (Run transcribe_project first.)"
        ])
    }
}
