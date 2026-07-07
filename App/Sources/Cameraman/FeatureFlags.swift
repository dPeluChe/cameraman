//
//  FeatureFlags.swift
//  App
//
//  Hidden switches for features that exist but aren't ready for users.
//

import Foundation

enum FeatureFlags {
    /// Auto-zoom suggestions: generate zoom keyframes from telemetry click
    /// windows. Enabled by default — the pipeline is stable and the manual
    /// zoom merge (PR #41) lets users override anything the auto-zoom produces.
    /// Disable for development with:
    ///   defaults write dev.dpeluche.CameramanApp.debug feature.autoZoom -bool NO
    static var autoZoom: Bool {
        UserDefaults.standard.object(forKey: "feature.autoZoom") as? Bool ?? true
    }
}
