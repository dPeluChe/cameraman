//
//  TimelineView+Thumbnails.swift
//  App
//
//  Extracted from TimelineView.swift (Phase 1 refactor, v0.5.1).
//  Thumbnail and waveform generation/lookup helpers.
//

import SwiftUI
import EngineKit

extension TimelineView {
    func initializeThumbnailCache(projectDirectory: String) {
        thumbnailTask?.cancel()
        let cache = ThumbnailCache(configuration: .default)
        thumbnailTask = Task {
            await cache.setProject(project, projectDirectory: projectDirectory)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.thumbnailCache = cache
            }
            await generateInitialThumbnails(count: 15)
            Task(priority: .utility) {
                await generateInitialWaveforms()
                await generateInitialThumbnails(count: 50)
            }
        }
    }

    func generateInitialThumbnails(count: Int = 50) async {
        guard let cache = thumbnailCache else { return }

        let duration = project.timeline.duration
        let thumbnailCount = min(count, Int(duration) + 1)
        let interval = duration / Double(max(thumbnailCount - 1, 1))

        var newThumbnails: [TimeInterval: NSImage] = [:]

        for i in 0..<thumbnailCount {
            guard !Task.isCancelled else { return }
            let time = Double(i) * interval

            if thumbnails[time] != nil {
                newThumbnails[time] = thumbnails[time]
                continue
            }

            do {
                let cachedThumbnail = try await cache.getThumbnail(at: time)
                if let image = NSImage(data: cachedThumbnail.imageData) {
                    newThumbnails[time] = image
                }
            } catch {
                // Thumbnails are optional UI enhancement; ignore errors.
            }
        }

        await MainActor.run {
            self.thumbnails = newThumbnails
        }
    }

    func generateInitialWaveforms() async {
        guard let cache = thumbnailCache else { return }

        var newWaveforms: [String: [Float]] = [:]

        if let audio = project.primarySources?.audio, let systemAudio = audio.system {
            do {
                let cachedWaveform = try await cache.getWaveform(for: systemAudio.path)
                newWaveforms[systemAudio.path] = cachedWaveform.samples
            } catch {
                // Waveforms are optional UI enhancement; ignore errors.
            }
        }

        if let audio = project.primarySources?.audio, let micAudio = audio.mic {
            do {
                let cachedWaveform = try await cache.getWaveform(for: micAudio.path)
                newWaveforms[micAudio.path] = cachedWaveform.samples
            } catch {
                // Waveforms are optional UI enhancement; ignore errors.
            }
        }

        await MainActor.run {
            self.waveforms = newWaveforms
        }
    }

    func getWaveformForTrack(_ trackKind: TimelineTrackKind) -> [Float]? {
        let trackPath: String?

        switch trackKind {
        case .systemAudio:
            trackPath = project.primarySources?.audio?.system?.path
        case .micAudio:
            trackPath = project.primarySources?.audio?.mic?.path
        default:
            trackPath = nil
        }

        guard let path = trackPath else { return nil }
        return waveforms[path]
    }
}
