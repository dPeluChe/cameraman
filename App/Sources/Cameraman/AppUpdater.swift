//
//  AppUpdater.swift
//  App
//
//  Checks GitHub releases for a newer version of Project Studio and
//  presents an NSAlert with the result. Background checks are silent
//  on failure; user-initiated checks always report a result.
//

import AppKit
import Foundation

@MainActor
final class AppUpdater {
    static let shared = AppUpdater()
    private init() {}

    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    private let releasesURL = URL(string: "https://api.github.com/repos/dPeluChe/labs-cameraman/releases/latest")!

    func checkForUpdates(userInitiated: Bool = false) {
        Task {
            do {
                var request = URLRequest(url: releasesURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let tag = json["tag_name"] as? String
                else {
                    if userInitiated { showError("Unable to reach the update server.") }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let releaseURL = (json["html_url"] as? String).flatMap(URL.init)

                if isNewer(latest, than: currentVersion) {
                    showUpdateAvailable(version: latest, releaseURL: releaseURL)
                } else if userInitiated {
                    let alert = NSAlert()
                    alert.messageText = "You're up to date"
                    alert.informativeText = "Project Studio \(currentVersion) is the latest version."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            } catch {
                if userInitiated { showError("No internet connection or update server unavailable.") }
            }
        }
    }

    private func isNewer(_ v1: String, than v2: String) -> Bool {
        v1.compare(v2, options: .numeric) == .orderedDescending
    }

    private func showUpdateAvailable(version: String, releaseURL: URL?) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Project Studio \(version) is available.\nYou have version \(currentVersion)."
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL ?? AppLinks.releases)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - App-wide links

enum AppLinks {
    static let help      = URL(string: "https://github.com/dPeluChe/labs-cameraman#readme")!
    static let releases  = URL(string: "https://github.com/dPeluChe/labs-cameraman/releases")!
    static let repo      = URL(string: "https://github.com/dPeluChe/labs-cameraman")!
    static let contact   = URL(string: "mailto:antonio@dpeluche.dev?subject=Project%20Studio%20Support")!
    static let sponsors  = URL(string: "https://github.com/sponsors/dPeluChe")!
    static let paypal    = URL(string: "https://paypal.me/dpeluche")!
    // static let website = URL(string: "https://...")!  — add when landing is live
}
