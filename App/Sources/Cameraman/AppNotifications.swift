//
//  AppNotifications.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import Foundation

extension Notification.Name {
    /// Notification posted when a project is updated (e.g. new take added)
    static let projectUpdated = Notification.Name("projectUpdated")
    /// Notification posted to open the recording controls window
    static let openRecordingWindow = Notification.Name("openRecordingWindow")
    /// Notification posted to open the export modal in the current editor
    static let openExportModal = Notification.Name("openExportModal")
    /// Notification posted to open the transcription / captions modal in the current editor
    static let openTranscriptionModal = Notification.Name("openTranscriptionModal")
    /// Notification posted to open the AI suggestions modal in the current editor
    static let openAISuggestions = Notification.Name("openAISuggestions")
    /// Notification posted to select/expand a tool in the editor right panel.
    /// Object is the `EditorTool.rawValue` string.
    static let selectEditorTool = Notification.Name("selectEditorTool")
}
