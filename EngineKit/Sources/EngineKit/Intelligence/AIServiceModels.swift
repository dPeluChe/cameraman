//
//  AIServiceModels.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

extension AIService {
    /// Silent region in audio
    struct SilentRegion {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let duration: TimeInterval
    }

    /// Chapter suggestion from transcript
    struct ChapterSuggestion {
        let title: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let confidence: Double
        let summary: String
        let keywords: [String]
    }

    /// Transcript model for AI analysis
    struct Transcript: Codable {
        let segments: [Segment]

        struct Segment: Codable {
            let startTime: TimeInterval
            let endTime: TimeInterval
            let text: String
        }
    }
}
