//
//  MCPTools+Delivery.swift
//  cameraman-mcp
//
//  Closes the edit→deliver loop: render a project (export_project) and track the
//  async render/transcribe jobs (get_job_status / list_jobs / cancel_job), plus
//  on-device transcription (transcribe_project) and reading the captions back.
//  All jobs live in ProjectLibrary.shared's in-memory JobQueue, so they're
//  pollable across tool calls within one server session.
//

import Foundation
import EngineKit

extension MCPTools {

    // MARK: - Export

    private static let presetsById: [String: ExportPreset] = [
        "web_1080_h264": .web1080h264,
        "high_1080_hevc": .high1080hevc,
        "portrait_1080_h264": .portrait1080h264,
        "ultra_4k_hevc": .ultra4kHevc,
        "animated_gif": .animatedGIF
    ]
    static var presetIds: [String] { presetsById.keys.sorted() }

    func exportProject(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let presetId = args.optStr("preset") ?? "web_1080_h264"
        guard let preset = Self.presetsById[presetId] else {
            throw MCPToolError("Unknown preset '\(presetId)'. Valid presets: \(Self.presetIds.joined(separator: ", "))")
        }
        let burnCaptions = (try? args.bool("burnCaptions")) ?? false
        let filename = args.optStr("filename")

        let engine = try await ProjectLibrary.shared.getExportEngine()
        let jobId: JobId
        if preset.id == "animated_gif" {
            jobId = try await engine.exportGIF(
                projectId: projectId, preset: preset,
                options: ExportOptions(outputFilename: filename, gifOptions: .default)
            )
        } else {
            jobId = try await engine.export(
                projectId: projectId, preset: preset,
                options: ExportOptions(burnCaptions: burnCaptions, outputFilename: filename)
            )
        }
        return try startedJob(jobId,
            "Export started. Poll get_job_status with this jobId; on success the file is in the project's renders/ folder.",
            extra: ["preset": preset.id])
    }

    /// Standard response for the async-job tools (export / transcribe / suggest):
    /// the jobId to poll, a started status, and a human message.
    func startedJob(_ jobId: JobId, _ message: String, extra: [String: Any] = [:]) throws -> String {
        var payload: [String: Any] = ["jobId": jobId.uuidString, "status": "started", "message": message]
        for (key, value) in extra { payload[key] = value }
        return try json(payload)
    }

    // MARK: - Jobs

    func getJobStatus(_ args: [String: Any]) async throws -> String {
        let jobId = try args.uuid("jobId")
        let queue = try await ProjectLibrary.shared.getJobQueue()
        guard let job = await queue.getJob(jobId: jobId) else {
            throw MCPToolError("No job with id \(jobId). Jobs are in-memory for this server session and are lost on restart.")
        }
        return try json(Self.jobPayload(job))
    }

    func listJobs(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let queue = try await ProjectLibrary.shared.getJobQueue()
        let jobs = await queue.listJobs(for: projectId)
        return try json(["jobs": jobs.map { Self.jobPayload($0) }])
    }

    func cancelJob(_ args: [String: Any]) async throws -> String {
        let jobId = try args.uuid("jobId")
        let queue = try await ProjectLibrary.shared.getJobQueue()
        try await queue.cancelJob(jobId: jobId)
        return "Canceled job \(jobId)"
    }

    private static func jobPayload(_ job: Job) -> [String: Any] {
        let statusName: String
        switch job.status {
        case .queued: statusName = "queued"
        case .running: statusName = "running"
        case .success: statusName = "success"
        case .failed: statusName = "failed"
        case .canceled: statusName = "canceled"
        }
        var payload: [String: Any] = [
            "jobId": job.jobId.uuidString,
            "type": job.type.rawValue,
            "projectId": job.projectId.uuidString,
            "status": statusName,
            "progress": job.status.progress,
            "startedAt": ISO8601DateFormatter().string(from: job.startedAt)
        ]
        if let completedAt = job.completedAt {
            payload["completedAt"] = ISO8601DateFormatter().string(from: completedAt)
        }
        if let error = job.error {
            payload["error"] = ["code": error.code, "message": error.message]
        }
        return payload
    }

    // MARK: - Transcription

    func transcribeProject(_ args: [String: Any]) async throws -> String {
        guard TranscriptionEngine.isAvailable else {
            throw MCPToolError("On-device transcription is unavailable on this hardware (requires Apple Silicon).")
        }
        let projectId = try args.uuid("projectId")
        let modelRaw = args.optStr("model") ?? "base"
        guard let model = TranscriptionEngine.Options.Model(rawValue: modelRaw) else {
            throw MCPToolError("Unknown model '\(modelRaw)'. Valid models: base, small, medium, large.")
        }
        let language = args.optStr("language")
        let translate = (try? args.bool("translate")) ?? false

        let engine = try await ProjectLibrary.shared.getTranscriptionEngine()
        let jobId = try await engine.transcribe(
            projectId: projectId,
            options: TranscriptionEngine.Options(model: model, language: language, translate: translate)
        )
        return try startedJob(jobId,
            "Transcription started. Poll get_job_status; on success read the captions with get_captions.")
    }

    func getCaptions(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let format = (args.optStr("format") ?? "srt").lowercased()
        let relativePath: String
        switch format {
        case "srt": relativePath = "transcript/captions.srt"
        case "vtt": relativePath = "transcript/captions.vtt"
        case "json", "transcript": relativePath = "transcript/transcript.json"
        default: throw MCPToolError("Unknown format '\(format)'. Use srt, vtt or json.")
        }
        let dir = try await ProjectLibrary.shared.getProjectDirectory(projectId: projectId)
        let url = dir.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            throw MCPToolError("No captions at \(relativePath). Run transcribe_project and wait for the job to finish first.")
        }
        return text
    }

    /// Generate editable subtitle cues on the timeline from the project's
    /// transcript (the app's "Add to Timeline"). They render over the video and
    /// burn into exports when `burnCaptions` is set.
    func addSubtitles(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let dir = try await ProjectLibrary.shared.getProjectDirectory(projectId: projectId)
        let url = dir.appendingPathComponent("transcript/transcript.json")
        guard let data = try? Data(contentsOf: url),
              let transcript = try? JSONDecoder().decode(TranscriptionEngine.Transcript.self, from: data) else {
            throw MCPToolError("No transcript found. Run transcribe_project and wait for the job to finish first.")
        }
        var project = try await loadProject(args)
        let count = project.setSubtitles(
            fromSegments: transcript.segments.map { (text: $0.text, start: $0.start, end: $0.end) }
        )
        try await ProjectLibrary.shared.updateProject(project)
        return try summary("Added \(count) subtitle cues to the timeline from the transcript.", project)
    }

    // MARK: - JSON helper

    /// Serialize a heterogeneous dictionary (mixed String/number/Bool/array)
    /// — JSONEncoder can't, so use JSONSerialization like `summary` does.
    func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
