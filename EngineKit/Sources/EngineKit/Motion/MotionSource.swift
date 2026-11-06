//
//  MotionSource.swift
//  EngineKit
//
//  What a motion was rendered from, kept next to its video so it can be changed and re-rendered.
//  A clip only references the video: this sidecar needs no project format change.
//

import Foundation

public struct MotionSource: Codable, Equatable, Sendable {
    public var template: String?
    public var html: String?
    public var title = ""
    public var subtitle = ""
    public var value = ""
    public var labels: [String] = []
    public var values: [Double] = []
    public var colorHex = "#0A84FF"
    public var duration: TimeInterval?

    public init() {}

    public static func sidecar(of video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("json")
    }

    public static func load(for video: URL) -> MotionSource? {
        guard let data = try? Data(contentsOf: sidecar(of: video)) else { return nil }
        return try? JSONDecoder().decode(MotionSource.self, from: data)
    }

    public func save(for video: URL) throws {
        try JSONEncoder().encode(self).write(to: Self.sidecar(of: video), options: .atomic)
    }
}

public enum MotionAssets {
    /// A file this young may be a render whose clip is not in the project yet.
    public static let minimumAge: TimeInterval = 3600

    /// Removes rendered motions no clip uses. Run it only when no undo history can bring one
    /// back, which is why deleting a clip keeps its file. Returns how many videos went.
    @discardableResult
    public static func removeUnused(in project: Project, directory: URL, now: Date = Date()) -> Int {
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: assets.path) else { return 0 }

        let used = Set(project.timeline.tracks.flatMap(\.clips).compactMap { clip -> String? in
            guard case .video(let ref) = clip.content else { return nil }
            return (ref.path as NSString).lastPathComponent
        })
        var removed = 0
        for name in names where name.hasPrefix("motion-") && name.hasSuffix(".mov") && !used.contains(name) {
            let file = assets.appendingPathComponent(name)
            let modified = (try? fileManager.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
            guard let modified, now.timeIntervalSince(modified) >= minimumAge else { continue }
            try? fileManager.removeItem(at: file)
            try? fileManager.removeItem(at: MotionSource.sidecar(of: file))
            removed += 1
        }
        return removed
    }
}
