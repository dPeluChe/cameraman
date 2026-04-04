//
//  ViewModelProtocol.swift
//  App
//
//  Standard protocol for ViewModels with loading/error states
//

import Foundation

/// Standard states for ViewModels
enum ViewModelState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

/// Protocol for standardizing ViewModel behavior
/// Provides consistent loading/error handling across all ViewModels
protocol ViewModelProtocol: ObservableObject {
    /// Current state of the ViewModel
    var state: ViewModelState { get }
    
    /// Convenience computed property for error message
    var errorMessage: String? { get }
    
    /// Check if currently loading
    var isLoading: Bool { get }
}

/// Default implementations
extension ViewModelProtocol {
    var errorMessage: String? {
        if case .error(let message) = state {
            return message
        }
        return nil
    }
    
    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }
}