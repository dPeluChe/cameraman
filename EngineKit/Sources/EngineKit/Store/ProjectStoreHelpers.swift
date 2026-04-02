//
//  ProjectStoreHelpers.swift
//  EngineKit
//
//  Extracted from ProjectStore.swift — file management, migration, and directory helpers
//

import Foundation
import AVFoundation

extension ProjectStore {
    /// Detect video dimensions from a file URL
    func detectVideoDimensions(at url: URL) async -> (width: Int, height: Int)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else {
            return nil
        }
        return (width: Int(size.width), height: Int(size.height))
    }

    /// Move recording files from Recorder.RecordingResult into the project sources directory
    func moveRecordingFiles(_ result: Recorder.RecordingResult, to sourcesPath: URL, takeId: UUID) async throws -> Project.Sources {
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
            let cameraDims = await detectVideoDimensions(at: destCameraPath)
            camera = Project.Sources.MediaTrack(
                path: "sources/\(cameraFilename)",
                fps: 30.0,
                size: Project.Sources.Size(w: cameraDims?.width ?? 1280, h: cameraDims?.height ?? 720),
                syncOffsetMs: Int(result.syncMetadata.cameraSyncOffsetMs),
                sha256: sha256(of: destCameraPath),
                sizeBytes: fileSize(of: destCameraPath)
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
                sha256: sha256(of: destSystemAudioPath),
                sizeBytes: fileSize(of: destSystemAudioPath)
            )

            var micAudioTrack: Project.Sources.AudioTracks.AudioTrack?
            if let micAudioPath = result.micAudioPath {
                let micAudioFilename = "\(prefix)_mic_audio.m4a"
                let destMicAudioPath = sourcesPath.appendingPathComponent(micAudioFilename)
                try fileManager.moveItem(at: micAudioPath, to: destMicAudioPath)
                micAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                    path: "sources/\(micAudioFilename)",
                    syncOffsetMs: Int(result.syncMetadata.micAudioSyncOffsetMs),
                    sha256: sha256(of: destMicAudioPath),
                    sizeBytes: fileSize(of: destMicAudioPath)
                )
            }

            audio = Project.Sources.AudioTracks(system: systemAudioTrack, mic: micAudioTrack)
        }

        // Move telemetry files
        var telemetry: Project.Sources.TelemetryTracks?
        if let telemetrySrc = result.telemetryPath {
            let telemetryDir = sourcesPath.deletingLastPathComponent().appendingPathComponent("telemetry", isDirectory: true)
            let cursorFilename = "\(prefix)_cursor.jsonl"
            let destCursorPath = telemetryDir.appendingPathComponent(cursorFilename)
            do {
                try fileManager.moveItem(at: telemetrySrc, to: destCursorPath)
                telemetry = Project.Sources.TelemetryTracks(
                    cursor: Project.Sources.TelemetryTracks.TelemetryTrack(path: "telemetry/\(cursorFilename)"),
                    keys: nil
                )
            } catch {
                // Telemetry file missing — non-fatal, continue without it
            }
        }

        // Detect actual video dimensions
        let screenDims = await detectVideoDimensions(at: screenPath)

        return Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/\(screenFilename)",
                fps: 60.0,
                size: Project.Sources.Size(w: screenDims?.width ?? 1920, h: screenDims?.height ?? 1080),
                syncOffsetMs: 0,
                sha256: sha256(of: screenPath),
                sizeBytes: fileSize(of: screenPath)
            ),
            camera: camera,
            audio: audio,
            telemetry: telemetry
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
