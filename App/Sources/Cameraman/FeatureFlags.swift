//
//  FeatureFlags.swift
//  App
//
//  Hidden switches for features that exist but aren't ready for users.
//

import Foundation

enum FeatureFlags {
    /// Auto-zoom suggestions confuse testers (timing/intensity need tuning), so
    /// the whole flow — generation, timeline markers, Apply button, auto-apply —
    /// is hidden by default. Re-enable for development with:
    ///   defaults write dev.dpeluche.CameramanApp.debug feature.autoZoom -bool YES
    static var autoZoom: Bool {
        UserDefaults.standard.bool(forKey: "feature.autoZoom")
    }
}
