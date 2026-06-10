//
//  ProjectStore+Merge.swift
//  EngineKit
//
//  Merge two projects into a new one: B's timeline is appended after A's,
//  with all source media copied and time-based metadata offset.
//

import Foundation

extension ProjectStore {

    /// Merge two projects into a brand-new project whose timeline is `firstId`'s
    /// content followed by `secondId`'s. Source files, takes, chapters, overlays and
    /// media items from both are carried over; the originals are left untouched.
    /// - Returns: The new (merged) project's id.
    public func mergeProjects(
        _ firstId: ProjectId,
        _ secondId: ProjectId,
        name: String? = nil
    ) async throws -> ProjectId {
        guard firstId != secondId else {
            throw EngineKitError.invalidConfiguration("Cannot merge a project with itself")
        }

        var first = normalizedForMerge(try await loadProject(projectId: firstId))
        var second = normalizedForMerge(try await loadProject(projectId: secondId))

        let firstDir = try projectDirectoryURL(for: firstId)
        let secondDir = try projectDirectoryURL(for: secondId)

        // New project directory
        let mergedId = ProjectId()
        let mergedDir = baseDirectory.appendingPathComponent(mergedId.uuidString, isDirectory: true)
        try createProjectDirectoryStructure(at: mergedDir)

        do {
            try copyMergeAssets(from: firstDir, into: mergedDir)
            try copyMergeAssets(from: secondDir, into: mergedDir)
        } catch {
            // Don't leave a half-built project behind
            try? fileManager.removeItem(at: mergedDir)
            throw error
        }

        // Thumbnail from the first project (regenerated on next edit anyway)
        let thumbSrc = firstDir.appendingPathComponent("thumbnail.jpg")
        if fileManager.fileExists(atPath: thumbSrc.path) {
            try? fileManager.copyItem(at: thumbSrc, to: mergedDir.appendingPathComponent("thumbnail.jpg"))
        }

        // --- Timeline: B after A ---
        let offset = first.timeline.duration
        second.timeline = Self.offsetTimeline(second.timeline, by: offset)

        var tracks: [Project.TimelineTrack] = []
        let primaryClips = (first.timeline.primaryTrack?.clips ?? []) + (second.timeline.primaryTrack?.clips ?? [])
        tracks.append(Project.TimelineTrack(id: Project.TimelineTrack.primaryTrackId, type: .primary, clips: primaryClips))
        tracks += first.timeline.tracks.filter { $0.type != .primary }
        tracks += second.timeline.tracks.filter { $0.type != .primary }

        let mergedTimeline = Project.Timeline(
            duration: first.timeline.duration + second.timeline.duration,
            tracks: tracks
        )

        // --- Time-based metadata from B shifted by A's duration ---
        let shiftedChapters = second.chapters.map { ch in
            Project.Chapter(
                id: ch.id,
                title: ch.title,
                startTime: ch.startTime + offset,
                endTime: ch.endTime + offset,
                summary: ch.summary,
                keywords: ch.keywords,
                createdAt: ch.createdAt
            )
        }
        let shiftedOverlays = second.overlays.map { overlay -> Project.Overlay in
            var copy = overlay
            copy.start += offset
            copy.end += offset
            return copy
        }
        let shiftedMediaItems = second.mediaItems.map { item -> Project.MediaItem in
            var copy = item
            copy.timelineIn += offset
            return copy
        }

        let merged = Project(
            projectId: mergedId,
            name: name ?? "\(first.name) + \(second.name)",
            sources: nil,
            takes: first.takes + second.takes,
            timeline: mergedTimeline,
            canvas: first.canvas,
            overlays: first.overlays + shiftedOverlays,
            chapters: first.chapters + shiftedChapters,
            // Captions reference rendered SRT/VTT for a single timeline; merging them
            // isn't meaningful — regenerate via transcription on the merged project.
            captions: nil,
            tags: Array(Set(first.tags).union(second.tags)).sorted(),
            mediaItems: first.mediaItems + shiftedMediaItems
        )

        try await saveProject(merged)
        logger.info("Merged projects into \(mergedId.uuidString) (offset \(offset)s, \(merged.takes.count) takes)")
        return mergedId
    }

    // MARK: - Helpers

    /// Make take references explicit so they survive living next to another project's
    /// takes: legacy `sources` becomes a real Take, and clips with `takeId == nil`
    /// (meaning "first take") get pinned to this project's first take.
    private func normalizedForMerge(_ project: Project) -> Project {
        var project = project

        if project.takes.isEmpty, let legacySources = project.sources {
            project.takes = [Project.Take(name: "Take 1", sources: legacySources)]
            project.sources = nil
        }

        guard let firstTakeId = project.takes.first?.id else { return project }

        for trackIndex in project.timeline.tracks.indices {
            for clipIndex in project.timeline.tracks[trackIndex].clips.indices {
                if case .recording(var ref) = project.timeline.tracks[trackIndex].clips[clipIndex].content,
                   ref.takeId == nil {
                    ref.takeId = firstTakeId
                    project.timeline.tracks[trackIndex].clips[clipIndex].content = .recording(ref)
                }
            }
        }
        return project
    }

    /// Copy a source project's media into the merged project directory, preserving
    /// relative paths so clip/take references stay valid. Regenerable folders are
    /// skipped. A filename collision aborts the merge (only possible with legacy
    /// un-prefixed files; modern files are prefixed by takeId).
    private func copyMergeAssets(from sourceDir: URL, into destDir: URL) throws {
        try copyTree(
            from: sourceDir,
            to: destDir,
            skipping: ["project.json", "thumbnail.jpg", "cache", "proxies", "renders", "transcript"]
        )
    }

    /// Recursively merge-copy a directory tree. `skipping` applies to this level only.
    /// Shared with project bundle export (ProjectStore+Bundle).
    func copyTree(from source: URL, to dest: URL, skipping: Set<String> = []) throws {
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        let items = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for item in items where !skipping.contains(item.lastPathComponent) {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let itemDest = dest.appendingPathComponent(item.lastPathComponent, isDirectory: isDirectory)
            if isDirectory {
                try copyTree(from: item, to: itemDest)
            } else {
                try copyFileChecked(from: item, to: itemDest)
            }
        }
    }

    func copyFileChecked(from source: URL, to dest: URL) throws {
        guard !fileManager.fileExists(atPath: dest.path) else {
            throw EngineKitError.invalidConfiguration(
                "Merge file name collision: \(dest.lastPathComponent). Both projects contain a file with this name."
            )
        }
        try fileManager.copyItem(at: source, to: dest)
    }

    /// Shift every clip in a timeline forward by `offset` seconds.
    private static func offsetTimeline(_ timeline: Project.Timeline, by offset: TimeInterval) -> Project.Timeline {
        guard offset > 0 else { return timeline }
        var timeline = timeline
        for trackIndex in timeline.tracks.indices {
            for clipIndex in timeline.tracks[trackIndex].clips.indices {
                timeline.tracks[trackIndex].clips[clipIndex].timelineIn += offset
            }
        }
        return timeline
    }
}
