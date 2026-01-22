//
//  ProjectStore.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import os.log

/// ProjectStore manages project persistence on disk
public actor ProjectStore {
    /// Base directory for all projects
    private let baseDirectory: URL
    /// File manager for disk operations
    private let fileManager: FileManager
    /// Structured logging
    private let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "ProjectStore")

    /// Current schema version
    private let currentSchemaVersion = 2

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

    /// Create a new project from a recording result
    /// - Parameters:
    ///   - recordingResult: Result from recording session
    ///   - name: Project name (optional, auto-generated if nil)
    ///   - tags: Project tags (optional)
    /// - Returns: The created ProjectId
    /// - Throws: EngineKitError if creation fails
    public func createProject(from recordingResult: RecordingResult, name: String?, tags: [String]?) async throws -> ProjectId {
        let projectId = ProjectId()
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)

        // Create project directory structure
        try createProjectDirectoryStructure(at: projectDirectory)

        // Move source files to project
        let sourcesPath = projectDirectory.appendingPathComponent("sources", isDirectory: true)
        let screenPath = sourcesPath.appendingPathComponent("screen.mov")
        let telemetryPath = projectDirectory.appendingPathComponent("telemetry", isDirectory: true).appendingPathComponent("cursor.jsonl")

        try fileManager.moveItem(at: recordingResult.screenPath, to: screenPath)
        try fileManager.moveItem(at: recordingResult.telemetryPath, to: telemetryPath)

        var camera: Project.Sources.MediaTrack?
        if let cameraPath = recordingResult.cameraPath {
            let destCameraPath = sourcesPath.appendingPathComponent("camera.mov")
            try fileManager.moveItem(at: cameraPath, to: destCameraPath)
            // TODO: Calculate actual SHA256 and dimensions
            camera = Project.Sources.MediaTrack(
                path: "sources/camera.mov",
                fps: 30.0,
                size: Project.Sources.Size(w: 1280, h: 720),
                syncOffsetMs: 0,
                sha256: "placeholder",
                sizeBytes: 0
            )
        }

        var audio: Project.Sources.AudioTracks?
        if let systemAudioPath = recordingResult.systemAudioPath {
            let destSystemAudioPath = sourcesPath.appendingPathComponent("system_audio.m4a")
            try fileManager.moveItem(at: systemAudioPath, to: destSystemAudioPath)
            let systemAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                path: "sources/system_audio.m4a",
                syncOffsetMs: 0,
                sha256: "placeholder",
                sizeBytes: 0
            )

            var micAudioTrack: Project.Sources.AudioTracks.AudioTrack?
            if let micAudioPath = recordingResult.micAudioPath {
                let destMicAudioPath = sourcesPath.appendingPathComponent("mic_audio.m4a")
                try fileManager.moveItem(at: micAudioPath, to: destMicAudioPath)
                micAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                    path: "sources/mic_audio.m4a",
                    syncOffsetMs: 0,
                    sha256: "placeholder",
                    sizeBytes: 0
                )
            }

            audio = Project.Sources.AudioTracks(system: systemAudioTrack, mic: micAudioTrack)
        }

        // Create initial project
        let now = Date()
        let sources = Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/screen.mov",
                fps: 60.0,
                size: Project.Sources.Size(w: 2880, h: 1800),
                syncOffsetMs: 0,
                sha256: "placeholder",
                sizeBytes: 0
            ),
            camera: camera,
            audio: audio,
            telemetry: Project.Sources.TelemetryTracks(
                cursor: Project.Sources.TelemetryTracks.TelemetryTrack(path: "telemetry/cursor.jsonl"),
                keys: nil
            )
        )
        
        let takeId = UUID()
        let take = Project.Take(
            id: takeId,
            name: "Take 1",
            createdAt: now,
            sources: sources
        )

        let project = Project(
            projectId: projectId,
            name: name ?? "Untitled Recording",
            takes: [take],
            timeline: Project.Timeline(
                duration: recordingResult.duration,
                segments: [
                    Project.Timeline.Segment(
                        id: UUID().uuidString,
                        takeId: takeId,
                        sourceIn: 0,
                        sourceOut: recordingResult.duration,
                        timelineIn: 0,
                        speed: 1.0
                    )
                ]
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#0B0B0D", fitMode: nil),
                layout: Project.Canvas.Layout(
                    type: "pip",
                    camera: Project.Canvas.Layout.CameraPosition(x: 0.74, y: 0.72, w: 0.22, h: 0.22, cornerRadius: 18)
                )
            ),
            overlays: [],
            chapters: [],
            captions: nil,
            tags: tags ?? [],
            schemaVersion: currentSchemaVersion,
            createdAt: now,
            updatedAt: now
        )

        // Save project.json
        try await saveProject(project)

        return projectId
    }

    public func createProject(from recordingResult: Recorder.RecordingResult, name: String?, tags: [String]?) async throws -> ProjectId {
        let projectId = ProjectId()
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)

        try createProjectDirectoryStructure(at: projectDirectory)

        let sourcesPath = projectDirectory.appendingPathComponent("sources", isDirectory: true)
        let screenPath = sourcesPath.appendingPathComponent("screen.mov")
        try fileManager.moveItem(at: recordingResult.screenVideoPath, to: screenPath)

        var camera: Project.Sources.MediaTrack?
        if let cameraVideoPath = recordingResult.cameraVideoPath {
            let destCameraPath = sourcesPath.appendingPathComponent("camera.mov")
            try fileManager.moveItem(at: cameraVideoPath, to: destCameraPath)
            camera = Project.Sources.MediaTrack(
                path: "sources/camera.mov",
                fps: 30.0,
                size: Project.Sources.Size(w: 1280, h: 720),
                syncOffsetMs: Int(recordingResult.syncMetadata.cameraSyncOffsetMs),
                sha256: "placeholder",
                sizeBytes: 0
            )
        }

        var audio: Project.Sources.AudioTracks?
        if let systemAudioPath = recordingResult.systemAudioPath {
            let destSystemAudioPath = sourcesPath.appendingPathComponent("system_audio.m4a")
            try fileManager.moveItem(at: systemAudioPath, to: destSystemAudioPath)
            let systemAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                path: "sources/system_audio.m4a",
                syncOffsetMs: Int(recordingResult.syncMetadata.systemAudioSyncOffsetMs),
                sha256: "placeholder",
                sizeBytes: 0
            )

            var micAudioTrack: Project.Sources.AudioTracks.AudioTrack?
            if let micAudioPath = recordingResult.micAudioPath {
                let destMicAudioPath = sourcesPath.appendingPathComponent("mic_audio.m4a")
                try fileManager.moveItem(at: micAudioPath, to: destMicAudioPath)
                micAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                    path: "sources/mic_audio.m4a",
                    syncOffsetMs: Int(recordingResult.syncMetadata.micAudioSyncOffsetMs),
                    sha256: "placeholder",
                    sizeBytes: 0
                )
            }

            audio = Project.Sources.AudioTracks(system: systemAudioTrack, mic: micAudioTrack)
        }

        let now = Date()
        
        let sources = Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/screen.mov",
                fps: 60.0,
                size: Project.Sources.Size(w: 2880, h: 1800),
                syncOffsetMs: 0,
                sha256: "placeholder",
                sizeBytes: 0
            ),
            camera: camera,
            audio: audio,
            telemetry: nil
        )
        
        let takeId = UUID()
        let take = Project.Take(
            id: takeId,
            name: "Take 1",
            createdAt: now,
            sources: sources
        )

        let project = Project(
            projectId: projectId,
            name: name ?? "Untitled Recording",
            takes: [take],
            timeline: Project.Timeline(
                duration: recordingResult.duration,
                segments: [
                    Project.Timeline.Segment(
                        id: UUID().uuidString,
                        takeId: takeId,
                        sourceIn: 0,
                        sourceOut: recordingResult.duration,
                        timelineIn: 0,
                        speed: 1.0
                    )
                ]
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#0B0B0D", fitMode: nil),
                layout: Project.Canvas.Layout(
                    type: "pip",
                    camera: Project.Canvas.Layout.CameraPosition(x: 0.74, y: 0.72, w: 0.22, h: 0.22, cornerRadius: 18)
                )
            ),
            overlays: [],
            chapters: [],
            captions: nil,
            tags: tags ?? [],
            schemaVersion: currentSchemaVersion,
            createdAt: now,
            updatedAt: now
        )

        try await saveProject(project)

        return projectId
    }

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
    public func listProjects() async throws -> [ProjectSummary] {
        let directories = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var summaries: [ProjectSummary] = []

        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }

            let projectFile = directory.appendingPathComponent("project.json")

            guard fileManager.fileExists(atPath: projectFile.path) else { continue }

            do {
                let data = try Data(contentsOf: projectFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let project = try decoder.decode(Project.self, from: data)

                let summary = ProjectSummary(
                    projectId: project.projectId,
                    name: project.name,
                    createdAt: project.createdAt,
                    updatedAt: project.updatedAt,
                    tags: project.tags,
                    duration: project.timeline.duration,
                    thumbnailPath: nil // TODO: Generate thumbnail
                )

                summaries.append(summary)
            } catch {
                // Skip projects that fail to decode
                continue
            }
        }

        // Sort by updatedAt (newest first)
        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Helpers

    /// Create the directory structure for a new project
    private func createProjectDirectoryStructure(at url: URL) throws {
        let paths = [
            "sources",
            "telemetry",
            "cache/thumbnails",
            "cache/waveforms",
            "proxies",
            "renders",
            "transcript"
        ]

        for path in paths {
            let directory = url.appendingPathComponent(path, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Migrate a project to a newer schema version
    private func migrateProject(_ project: Project, to targetVersion: Int) async throws -> Project {
        var migratedProject = project

        // Apply migrations for each version
        for version in (project.schemaVersion + 1)...targetVersion {
            switch version {
            case 2:
                // Future migrations would go here
                break
            default:
                break
            }
            migratedProject.schemaVersion = version
        }

        // Save migrated project
        try await saveProject(migratedProject)

        return migratedProject
    }
}
