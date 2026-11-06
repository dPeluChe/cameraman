//
//  ProjectStore+Thumbnail.swift
//  EngineKit
//
//  The picture of a project in the library, written when the library first finds none. That one
//  path covers new recordings, imports, projects made by agents and those from older versions.
//

import AVFoundation
import Foundation
import ImageIO

extension Project {
    /// The first footage on the timeline, a moment in: recordings often open on a black or starting frame.
    func thumbnailSource() -> (path: String, time: TimeInterval)? {
        let lead = { (from: TimeInterval, to: TimeInterval) in from + min(1, (to - from) * 0.1) }
        for clip in timeline.primaryTrack?.clips ?? [] {
            guard let ref = clip.recordingRef,
                  let sources = takes.first(where: { $0.id == ref.takeId })?.sources ?? primarySources else { continue }
            return (sources.screen.path, lead(ref.sourceIn, ref.sourceOut))
        }
        for clip in timeline.tracks.filter({ $0.type != .audio }).flatMap(\.clips) {
            if case .video(let ref) = clip.content, RenderedAssets.renderedPath(of: clip, as: .motion) == nil {
                return (ref.path, lead(ref.sourceIn, ref.sourceOut))
            }
        }
        return nil
    }
}

extension ProjectStore {
    static let thumbnailName = "thumbnail.jpg"

    /// Returns how many were written. Projects with no footage keep the placeholder.
    public func generateMissingThumbnails() async -> Int {
        let missing = (try? await listProjects())?.filter { $0.thumbnailPath == nil } ?? []
        var written = 0
        for summary in missing {
            guard let project = try? await loadProject(projectId: summary.projectId),
                  let directory = try? projectDirectoryURL(for: summary.projectId),
                  let source = project.thumbnailSource(),
                  await Self.writeThumbnail(from: directory.appendingPathComponent(source.path), at: source.time,
                                            to: directory.appendingPathComponent(Self.thumbnailName)) else { continue }
            summaryCache[directory.appendingPathComponent("project.json")] = nil
            written += 1
        }
        return written
    }

    private static func writeThumbnail(from video: URL, at time: TimeInterval, to output: URL) async -> Bool {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        guard let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image,
              let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.jpeg" as CFString, 1, nil) else {
            LogWarning(.projectStore, "No thumbnail from \(video.lastPathComponent)")
            return false
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
