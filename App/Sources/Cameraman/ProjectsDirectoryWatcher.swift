//
//  ProjectsDirectoryWatcher.swift
//  App
//
//  Watches the Projects directory for top-level changes (a project folder
//  added/removed/renamed by the MCP server or another window) and fires a
//  callback so the library refreshes live, without re-activating the app.
//
//  Implementation: poll the directory's modification date every ~2s. Adding or
//  removing a project folder bumps the parent dir's mtime, so the check is a
//  single cheap stat and only fires loadProjects when something actually
//  changed. (DispatchSource.makeFileSystemObjectEventSource is unavailable on
//  this toolchain.) Edits *inside* a project don't change the parent mtime —
//  those still refresh on activation / manual reload.
//

import Foundation

@MainActor
final class ProjectsDirectoryWatcher {
    private var timer: Timer?
    private var directory: URL?
    private var lastModified: Date?

    /// Start polling `directory`. `onChange` runs on the main actor whenever the
    /// directory's modification date changes.
    func start(directory: URL, onChange: @escaping () -> Void) {
        stop()
        self.directory = directory
        lastModified = Self.modificationDate(of: directory)

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll(onChange) }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        directory = nil
        lastModified = nil
    }

    private func poll(_ onChange: @escaping () -> Void) {
        guard let directory else { return }
        let current = Self.modificationDate(of: directory)
        if current != lastModified {
            lastModified = current
            onChange()
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}
