//
//  ZoomEasing.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

extension ZoomPlanGenerator {
    /// Easing functions for smooth zoom animations
    public enum EasingFunction: String, Codable, Sendable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        case easeInQuad
        case easeOutQuad
        case easeInOutQuad
        case easeInCubic
        case easeOutCubic
        case easeInOutCubic

        /// Apply easing function to a progress value (0.0 to 1.0)
        func apply(to progress: Double) -> Double {
            let t = max(0.0, min(1.0, progress))
            switch self {
            case .linear:
                return t
            case .easeIn:
                return t * t
            case .easeOut:
                return t * (2.0 - t)
            case .easeInOut:
                return t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
            case .easeInQuad:
                return t * t
            case .easeOutQuad:
                return t * (2.0 - t)
            case .easeInOutQuad:
                return t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
            case .easeInCubic:
                return t * t * t
            case .easeOutCubic:
                return t * t * t + t * (t * (t - 1.0) - 1.0) + 1.0
            case .easeInOutCubic:
                return t < 0.5 ? 4.0 * t * t * t : (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0
            }
        }
    }
}
