//
//  RecordingStateManager.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import Combine
import EngineKit

/// Shared state manager for recording controls
class RecordingStateManager: ObservableObject {
    static let shared = RecordingStateManager()
    @Published var viewModel: RecordingControlViewModel?
    /// Project the next recording joins as a take. Lives here because the window and its
    /// view model may not exist yet when the editor asks for a new take.
    @Published var targetProjectId: ProjectId?
    private init() {}
}
