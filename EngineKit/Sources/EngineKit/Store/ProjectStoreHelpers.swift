//
//  ProjectStoreHelpers.swift
//  EngineKit
//
//  Extracted from ProjectStore.swift — file management, migration, and directory helpers
//

import Foundation

extension ProjectStore {
    /// Move recording files from Recorder.RecordingResult into the project sources directory
    func moveRecordingFiles(_ result: Recorder.RecordingResult, to sourcesPath: URL, takeId: UUID) throws -> Project.Sources {
        // Use takeId prefix to avoid collisions
        let prefix = takeId.uuidString.prefix(8)
        let screenFilename = "\(prefix)_screen.mov"
        let screenPath = sourcesPath.appendingPathComponent(screenFilename)

        try fileManager.moveItem(at: result.screenVideoPath, to: screenPath)

        var camera: Project.Sources.MediaTrack?
        if let cameraVideoPath = result.cameraVideoPath {
            let cameraFilename = "\(prefix)_camera.mov"
            let destCameraPath = sourcesPath.appendingPathComponent(cameraFilename)
            try fileManager.moveItem(at: cameraVideoPath, to: destCameraPath)
            camera = Project.Sources.MediaTrack(
                path: "sources/\(cameraFilename)",
                fps: 30.0,
                size: Project.Sources.Size(w: 1280, h: 720),
                syncOffsetMs: Int(result.syncMetadata.cameraSyncOffsetMs),
                sha256: "placeholder",
                sizeBytes: 0
            )
        }

        var audio: Project.Sources.AudioTracks?
        if let systemAudioPath = result.systemAudioPath {
            let sysAudioFilename = "\(prefix)_system_audio.m4a"
            let destSystemAudioPath = sourcesPath.appendingPathComponent(sysAudioFilename)
            try fileManager.moveItem(at: systemAudioPath, to: destSystemAudioPath)

            let systemAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                path: "sources/\(sysAudioFilename)",
                syncOffsetMs: Int(result.syncMetadata.systemAudioSyncOffsetMs),
                sha256: "placeholder",
                sizeBytes: 0
            )

            var micAudioTrack: Project.Sources.AudioTracks.AudioTrack?
            if let micAudioPath = result.micAudioPath {
                let micAudioFilename = "\(prefix)_mic_audio.m4a"
                let destMicAudioPath = sourcesPath.appendingPathComponent(micAudioFilename)
                try fileManager.moveItem(at: micAudioPath, to: destMicAudioPath)
                micAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                    path: "sources/\(micAudioFilename)",
                    syncOffsetMs: Int(result.syncMetadata.micAudioSyncOffsetMs),
                    sha256: "placeholder",
                    sizeBytes: 0
                )
            }

            audio = Project.Sources.AudioTracks(system: systemAudioTrack, mic: micAudioTrack)
        }

        return Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/\(screenFilename)",
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
    }

    /// Create the directory structure for a new project
    func createProjectDirectoryStructure(at url: URL) throws {
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
    func migrateProject(_ project: Project, to targetVersion: Int) async throws -> Project {
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
