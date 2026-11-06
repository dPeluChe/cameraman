//
//  Project+ClipNames.swift
//  EngineKit
//
//  Names people can tell apart on the timeline. Rendered clips have hashed file names, and
//  tracks made for overlapping motions share a name.
//

import Foundation

extension Project.Timeline {
    /// "Motion", or "Motion 1", "Motion 2" in timeline order when there are several.
    public var renderedClipNames: [String: String] {
        var names: [String: String] = [:]
        for (kind, title) in [(RenderedAssets.Kind.motion, "Motion"), (.music, "Music")] {
            let clips = tracks.flatMap(\.clips)
                .filter { RenderedAssets.renderedPath(of: $0, as: kind) != nil }
                .sorted { $0.timelineIn < $1.timelineIn }
            for (index, clip) in clips.enumerated() {
                names[clip.id] = clips.count > 1 ? "\(title) \(index + 1)" : title
            }
        }
        return names
    }

    /// The track's name, with a letter when others of its type share it. Nil for an unnamed track.
    public func label(of track: Project.TimelineTrack) -> String? {
        guard !track.name.isEmpty else { return nil }
        let twins = tracks.filter { $0.type == track.type && $0.name == track.name }
        guard twins.count > 1, let index = twins.firstIndex(where: { $0.id == track.id }), index < 26 else { return track.name }
        return "\(track.name) \(Character(UnicodeScalar(65 + UInt8(index))))"
    }
}
