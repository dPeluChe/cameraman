//
//  MusicSource.swift
//  EngineKit
//
//  What a piece of music is rendered from, kept next to its audio file.
//

import Foundation

public struct MusicSource: RenderSource, Equatable, Sendable {
    public static let kind = RenderedAssets.Kind.music
    public static let trackName = "Music"
    /// A bed under a voice. Scores are levelled alike, so this suits all of them.
    public static let defaultVolume = 0.25

    public var score: MusicScore
    public var options: MusicRenderOptions

    public init(score: MusicScore, options: MusicRenderOptions) {
        self.score = score
        self.options = options
    }
}
