//
//  ProjectStore+Create.swift
//  EngineKit
//
//  Project creation from recording results and take management.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

extension ProjectStore {

    // MARK: - Create from Recording (Legacy)

    public func createProject(from recordingResult: RecordingResult, name: String?, tags: [String]?) async throws -> ProjectId {
        let projectId = ProjectId()
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)

        try createProjectDirectoryStructure(at: projectDirectory)

        let sourcesPath = projectDirectory.appendingPathComponent("sources", isDirectory: true)
        let screenPath = sourcesPath.appendingPathComponent("screen.mov")
        let telemetryPath = projectDirectory.appendingPathComponent("telemetry", isDirectory: true).appendingPathComponent("cursor.jsonl")

        try fileManager.moveItem(at: recordingResult.screenPath, to: screenPath)
        try fileManager.moveItem(at: recordingResult.telemetryPath, to: telemetryPath)

        var camera: Project.Sources.MediaTrack?
        if let cameraPath = recordingResult.cameraPath {
            let destCameraPath = sourcesPath.appendingPathComponent("camera.mov")
            try fileManager.moveItem(at: cameraPath, to: destCameraPath)
            let cameraDims = await detectVideoDimensions(at: destCameraPath)
            camera = Project.Sources.MediaTrack(
                path: "sources/camera.mov",
                fps: 30.0,
                size: Project.Sources.Size(w: cameraDims?.width ?? 1280, h: cameraDims?.height ?? 720),
                syncOffsetMs: 0,
                sha256: sha256(of: destCameraPath),
                sizeBytes: fileSize(of: destCameraPath)
            )
        }

        var audio: Project.Sources.AudioTracks?
        if let systemAudioPath = recordingResult.systemAudioPath {
            let destSystemAudioPath = sourcesPath.appendingPathComponent("system_audio.m4a")
            try fileManager.moveItem(at: systemAudioPath, to: destSystemAudioPath)
            let systemAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                path: "sources/system_audio.m4a",
                syncOffsetMs: 0,
                sha256: sha256(of: destSystemAudioPath),
                sizeBytes: fileSize(of: destSystemAudioPath)
            )

            var micAudioTrack: Project.Sources.AudioTracks.AudioTrack?
            if let micAudioPath = recordingResult.micAudioPath {
                let destMicAudioPath = sourcesPath.appendingPathComponent("mic_audio.m4a")
                try fileManager.moveItem(at: micAudioPath, to: destMicAudioPath)
                micAudioTrack = Project.Sources.AudioTracks.AudioTrack(
                    path: "sources/mic_audio.m4a",
                    syncOffsetMs: 0,
                    sha256: sha256(of: destMicAudioPath),
                    sizeBytes: fileSize(of: destMicAudioPath)
                )
            }

            audio = Project.Sources.AudioTracks(system: systemAudioTrack, mic: micAudioTrack)
        }

        let now = Date()
        let screenDims = await detectVideoDimensions(at: screenPath)
        let sources = Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/screen.mov",
                fps: 60.0,
                size: Project.Sources.Size(w: screenDims?.width ?? 1920, h: screenDims?.height ?? 1080),
                syncOffsetMs: 0,
                sha256: sha256(of: screenPath),
                sizeBytes: fileSize(of: screenPath)
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
            name: name ?? Self.defaultProjectName(),
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
                    camera: Project.Canvas.Layout.CameraPosition(x: 0.72, y: 0.74, w: 0.26, h: 0.22, cornerRadius: 12)
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

        let thumbnailURL = projectDirectory.appendingPathComponent("thumbnail.jpg")
        generateThumbnail(from: screenPath, to: thumbnailURL)

        return projectId
    }

    // MARK: - Create from Recorder.RecordingResult

    public func createProject(from recordingResult: Recorder.RecordingResult, name: String?, tags: [String]?) async throws -> ProjectId {
        let projectId = ProjectId()
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)

        try createProjectDirectoryStructure(at: projectDirectory)

        let sourcesPath = projectDirectory.appendingPathComponent("sources", isDirectory: true)
        let takeId = UUID()
        let takeSources = try await moveRecordingFiles(recordingResult, to: sourcesPath, takeId: takeId)

        let screenFilePath = projectDirectory.appendingPathComponent(takeSources.screen.path)
        let screenDims = await detectVideoDimensions(at: screenFilePath)
        let screenW = screenDims?.width ?? 1920
        let screenH = screenDims?.height ?? 1080

        let sourceAspect = Double(screenW) / Double(screenH)
        let exportH = 1080
        let exportW = Int(Double(exportH) * sourceAspect)
        let finalW = exportW % 2 == 0 ? exportW : exportW + 1

        let now = Date()

        let take = Project.Take(
            id: takeId,
            name: "Take 1",
            createdAt: now,
            sources: takeSources
        )

        let project = Project(
            projectId: projectId,
            name: name ?? Self.defaultProjectName(),
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
                format: Project.Canvas.Format(aspect: "\(finalW):\(exportH)", w: finalW, h: exportH),
                background: Project.Canvas.Background(type: "solid", value: "#0B0B0D", fitMode: nil),
                layout: Project.Canvas.Layout(
                    type: "pip",
                    camera: Project.Canvas.Layout.CameraPosition(x: 0.72, y: 0.74, w: 0.26, h: 0.22, cornerRadius: 12)
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

    // MARK: - Empty Project

    /// Create a project with no recording — a blank 1920x1080 canvas the user
    /// fills by importing video/audio/images. A recording can be added later
    /// as Take 1 via addTake.
    public func createEmptyProject(name: String? = nil, tags: [String]? = nil) async throws -> ProjectId {
        let projectId = ProjectId()
        let projectDirectory = baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
        try createProjectDirectoryStructure(at: projectDirectory)

        let now = Date()
        let project = Project(
            projectId: projectId,
            name: name ?? Self.defaultProjectName(),
            takes: [],
            timeline: Project.Timeline(duration: 0, tracks: [
                Project.TimelineTrack(id: Project.TimelineTrack.primaryTrackId, type: .primary, clips: [])
            ]),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#0B0B0D", fitMode: nil),
                layout: Project.Canvas.Layout(type: "pip", camera: nil)
            ),
            tags: tags ?? [],
            schemaVersion: currentSchemaVersion,
            createdAt: now,
            updatedAt: now
        )

        try await saveProject(project)
        return projectId
    }

    // MARK: - Add Take

    public func addTake(projectId: ProjectId, recordingResult: Recorder.RecordingResult) async throws -> Project.Take {
        var project = try await loadProject(projectId: projectId)
        let projectDirectory = try projectDirectoryURL(for: projectId)
        let sourcesPath = projectDirectory.appendingPathComponent("sources", isDirectory: true)

        let takeId = UUID()
        let takeSources = try await moveRecordingFiles(recordingResult, to: sourcesPath, takeId: takeId)

        let takeNumber = project.takes.count + 1
        let take = Project.Take(
            id: takeId,
            name: "Take \(takeNumber)",
            createdAt: Date(),
            sources: takeSources
        )

        project.takes.append(take)
        try await saveProject(project)
        return take
    }

    // MARK: - Thumbnail

    func generateThumbnail(from videoURL: URL, to outputURL: URL) {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)

        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil),
              let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.jpeg" as CFString, 1, nil)
        else { return }

        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
