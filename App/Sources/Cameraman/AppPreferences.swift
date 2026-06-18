//
//  AppPreferences.swift
//  App
//
//  Defaults-backed accessors read by non-view code (parallel to FeatureFlags).
//

import Foundation
import EngineKit

/// Persisted transcription model choice, shared between the Settings UI and
/// TranscriptionViewModel.
enum TranscriptionModelPreference {
    static let key = "transcription.model"

    static var current: TranscriptionEngine.Options.Model {
        let raw = UserDefaults.standard.string(forKey: key) ?? TranscriptionEngine.Options.Model.base.rawValue
        return TranscriptionEngine.Options.Model(rawValue: raw) ?? .base
    }
}
