//
//  RecordingStateManager.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import Combine

/// Shared state manager for recording controls
class RecordingStateManager: ObservableObject {
    static let shared = RecordingStateManager()
    @Published var viewModel: RecordingControlViewModel?
    private init() {}
}
