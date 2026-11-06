//
//  MusicSource.swift
//  EngineKit
//
//  What a piece of music was rendered from, kept next to its audio file.
//

import Foundation

public struct MusicSource: RenderSource, Equatable, Sendable {
    public var style: String?
    public var code: String?
    public var duration: TimeInterval
    public var seed = 1
    public var bpm: Double?
    public var key: String?
    public var intensity = 0.5

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    public var options: MusicRenderOptions {
        MusicRenderOptions(duration: duration, seed: seed, bpm: bpm, key: key, intensity: intensity)
    }
}
