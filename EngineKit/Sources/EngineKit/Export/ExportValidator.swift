//
//  ExportValidator.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

extension ExportEngine {
    /// Validate that all source files exist
    func validateSourceFiles(for project: Project, projectId: ProjectId) async throws {
        let projectDirectory = try await projectStore.projectDirectoryURL(for: projectId)

        // 1. Validate primary sources if they exist (legacy projects)
        if let sources = project.sources {
            let screenURL = projectDirectory.appendingPathComponent(sources.screen.path)
            guard fileManager.fileExists(atPath: screenURL.path) else {
                throw ExportError.mediaFileNotFound(sources.screen.path)
            }

            if let camera = sources.camera {
                let cameraURL = projectDirectory.appendingPathComponent(camera.path)
                guard fileManager.fileExists(atPath: cameraURL.path) else {
                    throw ExportError.mediaFileNotFound(camera.path)
                }
            }

            if let systemAudio = sources.audio?.system {
                let audioURL = projectDirectory.appendingPathComponent(systemAudio.path)
                guard fileManager.fileExists(atPath: audioURL.path) else {
                    throw ExportError.mediaFileNotFound(systemAudio.path)
                }
            }

            if let micAudio = sources.audio?.mic {
                let micURL = projectDirectory.appendingPathComponent(micAudio.path)
                guard fileManager.fileExists(atPath: micURL.path) else {
                    throw ExportError.mediaFileNotFound(micAudio.path)
                }
            }
        }

        // 2. Validate sources for all takes used in the timeline
        let usedTakeIds = Set(project.timeline.segments.compactMap { $0.takeId })
        for takeId in usedTakeIds {
            guard let take = project.takes.first(where: { $0.id == takeId }) else {
                logger.warning("Segment references missing takeId: \(takeId)")
                continue
            }

            let sources = take.sources
            let screenURL = projectDirectory.appendingPathComponent(sources.screen.path)
            guard fileManager.fileExists(atPath: screenURL.path) else {
                throw ExportError.mediaFileNotFound(sources.screen.path)
            }

            if let camera = sources.camera {
                let cameraURL = projectDirectory.appendingPathComponent(camera.path)
                guard fileManager.fileExists(atPath: cameraURL.path) else {
                    throw ExportError.mediaFileNotFound(camera.path)
                }
            }

            if let systemAudio = sources.audio?.system {
                let audioURL = projectDirectory.appendingPathComponent(systemAudio.path)
                guard fileManager.fileExists(atPath: audioURL.path) else {
                    throw ExportError.mediaFileNotFound(systemAudio.path)
                }
            }

            if let micAudio = sources.audio?.mic {
                let micURL = projectDirectory.appendingPathComponent(micAudio.path)
                guard fileManager.fileExists(atPath: micURL.path) else {
                    throw ExportError.mediaFileNotFound(micAudio.path)
                }
            }
        }

        logger.info("All source files validated successfully")
    }

    /// Resolve sources for a specific take ID, falling back to primary sources
    func resolveSources(for takeId: UUID?, in project: Project) -> Project.Sources? {
        if let takeId = takeId, let take = project.takes.first(where: { $0.id == takeId }) {
            return take.sources
        }
        return project.primarySources
    }

    /// Get project directory for a given project ID
    func getProjectDirectory(for projectId: ProjectId) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDirectory = appSupport.appendingPathComponent("ProjectStudio/Projects", isDirectory: true)
        return baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
    }
}
