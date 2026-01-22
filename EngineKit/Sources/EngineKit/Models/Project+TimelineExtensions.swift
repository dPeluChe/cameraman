//
//  Project+TimelineExtensions.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

extension Project {
    /// Captions configuration
    public struct Captions: Codable, Equatable {
        public let language: String
        public let srtPath: String
        public let vttPath: String
    }

    /// Chapter marker for video navigation
    public struct Chapter: Codable, Equatable, Identifiable {
        /// Unique identifier
        public let id: UUID
        /// Chapter title (editable by user)
        public var title: String
        /// Chapter start time in seconds
        public let startTime: TimeInterval
        /// Chapter end time in seconds
        public let endTime: TimeInterval
        /// Optional chapter summary
        public var summary: String?
        /// Optional keywords for the chapter
        public var keywords: [String]
        /// Timestamp when chapter was created
        public let createdAt: Date

        /// Initialize a new chapter
        public init(
            id: UUID = UUID(),
            title: String,
            startTime: TimeInterval,
            endTime: TimeInterval,
            summary: String? = nil,
            keywords: [String] = [],
            createdAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.startTime = startTime
            self.endTime = endTime
            self.summary = summary
            self.keywords = keywords
            self.createdAt = createdAt
        }

        /// Chapter duration
        public var duration: TimeInterval {
            endTime - startTime
        }
    }
}
