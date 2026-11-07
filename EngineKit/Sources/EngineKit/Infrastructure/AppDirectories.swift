//
//  AppDirectories.swift
//  EngineKit
//
//  Where the app keeps its data, and the one-time move out of the sandbox container
//  (the app stopped being sandboxed in 0.8 so it can run the user's agent CLIs).
//

import Foundation

public enum AppDirectories {
    /// Application Support/ProjectStudio: projects, models and recordings. Debug app builds keep their own,
    /// as their sandbox containers did.
    public static var support: URL {
        let name = Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true ? "ProjectStudio-Debug" : "ProjectStudio"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }

    /// WhisperKit's download base, kept out of the user's Documents.
    public static var models: URL { support.appendingPathComponent("Models", isDirectory: true) }

    public static var recordings: URL { support.appendingPathComponent("Recordings", isDirectory: true) }
}

/// Moves what the sandboxed app kept in its container to the same places outside it.
/// Nothing is overwritten: a project or file already at the destination wins.
public struct ContainerMigration {
    public let container: URL
    public let support: URL

    /// `container` is ~/Library/Containers/<bundle id>/Data; `support` is the new Application Support/ProjectStudio.
    public init(container: URL, support: URL) {
        self.container = container
        self.support = support
    }

    public init(bundleIdentifier: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(container: home.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data", isDirectory: true),
                  support: AppDirectories.support)
    }

    /// Returns how many items moved.
    @discardableResult
    public func run() -> Int {
        let old = container.appendingPathComponent("Library/Application Support/ProjectStudio", isDirectory: true)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        var moved = 0
        for name in children(of: old) where name != "Models" && name != "Recordings" {
            moved += merge(old.appendingPathComponent(name), into: support.appendingPathComponent(name))
        }
        moved += merge(documents.appendingPathComponent("huggingface"), into: support.appendingPathComponent("Models"))
        moved += merge(documents.appendingPathComponent("Recordings"), into: support.appendingPathComponent("Recordings"))
        return moved
    }

    /// Settings the sandboxed app saved, for the keys this app has not set yet.
    public func importPreferences(into defaults: UserDefaults, bundleIdentifier: String) {
        let plist = container.appendingPathComponent("Library/Preferences/\(bundleIdentifier).plist")
        guard let values = NSDictionary(contentsOf: plist) as? [String: Any] else { return }
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    /// Moves `source` to `destination`, or its children one by one when the destination exists.
    private func merge(_ source: URL, into destination: URL) -> Int {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return 0 }
        if !fileManager.fileExists(atPath: destination.path) {
            try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            return (try? fileManager.moveItem(at: source, to: destination)) != nil ? 1 : 0
        }
        guard isDirectory.boolValue else { return 0 }
        return children(of: source).reduce(0) { total, name in
            total + merge(source.appendingPathComponent(name), into: destination.appendingPathComponent(name))
        }
    }

    private func children(of directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0 != ".DS_Store" }
    }
}
