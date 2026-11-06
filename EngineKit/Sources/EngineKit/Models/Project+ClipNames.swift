//
//  Project+ClipNames.swift
//  EngineKit
//
//  Names people can tell apart on the timeline. Rendered clips have hashed file names, and
//  tracks made for overlapping motions share a name.
//

import Foundation

extension Project.TimelineClip {
    fileprivate var plainName: String {
        switch content {
        case .video(let ref): return (ref.path as NSString).lastPathComponent
        case .audio(let ref): return (ref.path as NSString).lastPathComponent
        case .image(let ref): return (ref.path as NSString).lastPathComponent
        case .color: return "Color"
        case .recording: return "Recording"
        }
    }
}

extension Project.Timeline {
    /// By clip id. Renders read "Motion", or "Motion 1", "Motion 2" in timeline order when there are several.
    public var clipNames: [String: String] {
        let clips = tracks.flatMap(\.clips).sorted { $0.timelineIn < $1.timelineIn }
        var names = Dictionary(clips.map { ($0.id, $0.plainName) }, uniquingKeysWith: { first, _ in first })
        let sources: [any RenderSource.Type] = [MotionSource.self, MusicSource.self]
        for source in sources {
            let renders = clips.filter { RenderedAssets.renderedPath(of: $0, as: source.kind) != nil }
            for (index, clip) in renders.enumerated() {
                names[clip.id] = renders.count > 1 ? "\(source.trackName) \(index + 1)" : source.trackName
            }
        }
        return names
    }

    /// The track's name, with a letter when other visible tracks of its type share it. Nil for an unnamed track.
    public func label(of track: Project.TimelineTrack) -> String? {
        guard !track.name.isEmpty else { return nil }
        let twins = tracks.filter { $0.type == track.type && $0.name == track.name && !$0.clips.isEmpty }
        guard twins.count > 1, let index = twins.firstIndex(where: { $0.id == track.id }), index < 26 else { return track.name }
        return "\(track.name) \(Character(UnicodeScalar(65 + UInt8(index))))"
    }
}
