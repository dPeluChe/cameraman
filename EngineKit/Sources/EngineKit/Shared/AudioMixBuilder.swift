//
//  AudioMixBuilder.swift
//  EngineKit
//
//  Builds AVMutableAudioMix for per-track mute/volume control.
//  Used by both Preview and Export pipelines.
//

import Foundation
import AVFoundation

public struct AudioMixBuilder {

    /// Per-track mute/volume state
    public struct TrackMuteState: Codable, Equatable, Sendable {
        public var systemAudioMuted: Bool
        public var micAudioMuted: Bool
        public var systemAudioVolume: Float
        public var micAudioVolume: Float

        public init(
            systemAudioMuted: Bool = false,
            micAudioMuted: Bool = false,
            systemAudioVolume: Float = 1.0,
            micAudioVolume: Float = 1.0
        ) {
            self.systemAudioMuted = systemAudioMuted
            self.micAudioMuted = micAudioMuted
            self.systemAudioVolume = systemAudioVolume
            self.micAudioVolume = micAudioVolume
        }
    }

    /// Build an AVMutableAudioMix from composition tracks and mute state.
    /// Returns nil if there are no audio tracks to configure.
    public static func buildAudioMix(
        compositionResult: CompositionBuilder.Result,
        muteState: TrackMuteState
    ) -> AVMutableAudioMix? {
        var parameters: [AVMutableAudioMixInputParameters] = []

        if let systemTrack = compositionResult.systemAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: systemTrack)
            let volume = muteState.systemAudioMuted ? Float(0.0) : muteState.systemAudioVolume
            params.setVolume(volume, at: .zero)
            parameters.append(params)
        }

        if let micTrack = compositionResult.micAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: micTrack)
            let volume = muteState.micAudioMuted ? Float(0.0) : muteState.micAudioVolume
            params.setVolume(volume, at: .zero)
            parameters.append(params)
        }

        // Handle additional audio tracks (imported media)
        for additional in compositionResult.additionalAudioTracks {
            let params = AVMutableAudioMixInputParameters(track: additional.track)
            let volume = additional.mediaItem.isMuted ? Float(0.0) : Float(additional.mediaItem.volume)
            params.setVolume(volume, at: .zero)
            parameters.append(params)
        }

        guard !parameters.isEmpty else { return nil }

        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }

}
