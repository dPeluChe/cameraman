//
//  RenderedAssets.swift
//  EngineKit
//
//  Media rendered from code into a project's assets, and the source each file was made from. A clip
//  only references the file: the sidecar next to it needs no project format change.
//

import Foundation

/// What a rendered file was made from, stored beside it so it can be changed and rendered again.
public protocol RenderSource: Codable {
    static var kind: RenderedAssets.Kind { get }
}

extension RenderSource {
    public static func sidecar(of file: URL) -> URL { RenderedAssets.sidecar(of: file) }

    public static func load(for file: URL) -> Self? {
        guard let data = try? Data(contentsOf: sidecar(of: file)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public func save(for file: URL) throws {
        try JSONEncoder().encode(self).write(to: Self.sidecar(of: file), options: .atomic)
    }
}

public enum RenderedAssets {
    public enum Kind: CaseIterable, Sendable {
        case motion, music

        var prefix: String { "\(self)" }

        var fileExtension: String {
            switch self {
            case .motion: return "mov"
            case .music: return "m4a"
            }
        }
    }

    /// A file this young may be a render whose clip is not in the project yet.
    public static let minimumAge: TimeInterval = 3600

    public static func newFileName(_ kind: Kind) -> String {
        "\(kind.prefix)-\(UUID().uuidString.prefix(8).lowercased()).\(kind.fileExtension)"
    }

    /// Exact, because imported files keep their names and one could be called motion-intro.mov.
    public static func isRendered(_ name: String, as kind: Kind) -> Bool {
        name.range(of: "^\(kind.prefix)-[0-9a-f]{8}\\.\(kind.fileExtension)$", options: .regularExpression) != nil
    }

    static func sidecar(of file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("json")
    }

    /// Removes a render and its sidecar.
    public static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: sidecar(of: file))
    }

    /// Runs `render` on a new file in the project's assets and saves `source` beside it.
    /// Nothing is left behind if either step fails.
    public static func render<Source: RenderSource, Output>(
        _ source: Source, in directory: URL, _ render: (URL) async throws -> Output
    ) async throws -> (file: URL, output: Output) {
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let file = assets.appendingPathComponent(newFileName(Source.kind))
        return try await removing(file) {
            let output = try await render(file)
            try source.save(for: file)
            return (file, output)
        }
    }

    /// Runs `body`, removing the render if it fails, for a clip edit that may be refused.
    public static func removing<Output>(_ file: URL, ifFailing body: () async throws -> Output) async throws -> Output {
        do {
            return try await body()
        } catch {
            remove(file)
            throw error
        }
    }

    /// The file behind a clip, when it is a render of this kind.
    public static func renderedPath(of clip: Project.TimelineClip, as kind: Kind) -> String? {
        guard let path = mediaPath(of: clip), isRendered((path as NSString).lastPathComponent, as: kind) else { return nil }
        return path
    }

    private static func mediaPath(of clip: Project.TimelineClip) -> String? {
        switch clip.content {
        case .video(let ref): return ref.path
        case .audio(let ref): return ref.path
        default: return nil
        }
    }

    /// Removes renders no clip uses. Run it only when no undo history can bring one back, which is
    /// why deleting a clip keeps its file. Returns how many files went.
    @discardableResult
    public static func removeUnused(in project: Project, directory: URL, now: Date = Date()) -> Int {
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: assets.path) else { return 0 }

        let used = Set(project.timeline.tracks.flatMap(\.clips).compactMap(mediaPath).map { ($0 as NSString).lastPathComponent })
        var removed = 0
        for name in names where !used.contains(name) && Kind.allCases.contains(where: { isRendered(name, as: $0) }) {
            let file = assets.appendingPathComponent(name)
            let modified = (try? fileManager.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
            guard let modified, now.timeIntervalSince(modified) >= minimumAge else { continue }
            remove(file)
            removed += 1
        }
        return removed
    }
}
