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
    /// Survives until the recording window appears; its view model may not exist yet.
    var requestedTarget: ProjectId?
    private init() {}
}
