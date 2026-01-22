//
//  Project+Sources.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

extension Project {
    /// A Take represents a single recording session containing multiple media sources (screen, camera, mic, etc.)
    public struct Take: Codable, Equatable, Identifiable {
        public let id: UUID
        public var name: String
        public let createdAt: Date
        public var sources: Sources

        public init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = Date(),
            sources: Sources
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.sources = sources
        }
    }

    /// Source media tracks
    public struct Sources: Codable, Equatable {
        /// Which track is the sync reference
        public let syncReference: String
        /// Screen recording info
        public var screen: MediaTrack
        /// Camera recording info (optional)
        public var camera: MediaTrack?
        /// Audio tracks
        public var audio: AudioTracks?
        /// Telemetry data
        public var telemetry: TelemetryTracks?

        public init(
            syncReference: String = "screen",
            screen: MediaTrack,
            camera: MediaTrack? = nil,
            audio: AudioTracks? = nil,
            telemetry: TelemetryTracks? = nil
        ) {
            self.syncReference = syncReference
            self.screen = screen
            self.camera = camera
            self.audio = audio
            self.telemetry = telemetry
        }

        /// Media track information
        public struct MediaTrack: Codable, Equatable {
            /// Relative path to the file
            public let path: String
            /// Frame rate
            public let fps: Double
            /// Dimensions
            public let size: Size
            /// Sync offset in milliseconds
            public var syncOffsetMs: Int
            /// SHA256 checksum
            public let sha256: String
            /// File size in bytes
            public let sizeBytes: UInt64

            public init(
                path: String,
                fps: Double,
                size: Size,
                syncOffsetMs: Int = 0,
                sha256: String = "",
                sizeBytes: UInt64 = 0
            ) {
                self.path = path
                self.fps = fps
                self.size = size
                self.syncOffsetMs = syncOffsetMs
                self.sha256 = sha256
                self.sizeBytes = sizeBytes
            }
        }

        /// Dimensions
        public struct Size: Codable, Equatable {
            public let w: Int
            public let h: Int

            public init(w: Int, h: Int) {
                self.w = w
                self.h = h
            }
        }

        /// Audio tracks
        public struct AudioTracks: Codable, Equatable {
            /// System audio
            public var system: AudioTrack?
            /// Microphone audio
            public var mic: AudioTrack?

            public init(system: AudioTrack? = nil, mic: AudioTrack? = nil) {
                self.system = system
                self.mic = mic
            }

            public struct AudioTrack: Codable, Equatable {
                public let path: String
                public var syncOffsetMs: Int
                public let sha256: String
                public let sizeBytes: UInt64

                public init(
                    path: String,
                    syncOffsetMs: Int = 0,
                    sha256: String = "",
                    sizeBytes: UInt64 = 0
                ) {
                    self.path = path
                    self.syncOffsetMs = syncOffsetMs
                    self.sha256 = sha256
                    self.sizeBytes = sizeBytes
                }
            }
        }

        /// Telemetry data
        public struct TelemetryTracks: Codable, Equatable {
            public let cursor: TelemetryTrack?
            public let keys: TelemetryTrack?

            public init(cursor: TelemetryTrack? = nil, keys: TelemetryTrack? = nil) {
                self.cursor = cursor
                self.keys = keys
            }

            public struct TelemetryTrack: Codable, Equatable {
                public let path: String

                public init(path: String) {
                    self.path = path
                }
            }
        }
    }
}
