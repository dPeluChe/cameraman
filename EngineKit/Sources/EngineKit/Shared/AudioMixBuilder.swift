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

        /// Default mic volume is boosted to compensate for typically lower mic input levels vs system audio
        public init(
            systemAudioMuted: Bool = false,
            micAudioMuted: Bool = false,
            systemAudioVolume: Float = 1.0,
            micAudioVolume: Float = 2.5
        ) {
            self.systemAudioMuted = systemAudioMuted
            self.micAudioMuted = micAudioMuted
            self.systemAudioVolume = systemAudioVolume
            self.micAudioVolume = micAudioVolume
        }
    }

    /// Build an AVMutableAudioMix from composition tracks and mute state.
    /// Supports per-segment volume/mute overrides via timeline segments.
    /// Returns nil if there are no audio tracks to configure.
    public static func buildAudioMix(
        compositionResult: CompositionBuilder.Result,
        muteState: TrackMuteState,
        segments: [Project.Timeline.Segment] = []
    ) -> AVMutableAudioMix? {
        let hasSegmentOverrides = segments.contains { $0.volume != nil || $0.audioMuted != nil }
        var parameters: [AVMutableAudioMixInputParameters] = []

        if let systemTrack = compositionResult.systemAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: systemTrack)
            let globalVolume = muteState.systemAudioMuted ? Float(0.0) : muteState.systemAudioVolume
            if hasSegmentOverrides {
                applySegmentVolumes(params: params, globalVolume: globalVolume, segments: segments)
            } else {
                params.setVolume(globalVolume, at: .zero)
            }
            parameters.append(params)
        }

        if let micTrack = compositionResult.micAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: micTrack)
            let globalVolume = muteState.micAudioMuted ? Float(0.0) : muteState.micAudioVolume
            if hasSegmentOverrides {
                applySegmentVolumes(params: params, globalVolume: globalVolume, segments: segments)
            } else {
                params.setVolume(globalVolume, at: .zero)
            }
            parameters.append(params)
        }

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

    /// Apply per-segment volume ramps to audio mix parameters
    private static func applySegmentVolumes(
        params: AVMutableAudioMixInputParameters,
        globalVolume: Float,
        segments: [Project.Timeline.Segment]
    ) {
        for segment in segments {
            let start = CMTime(seconds: segment.timelineIn, preferredTimescale: 600)
            let duration = CMTime(seconds: segment.timelineDuration, preferredTimescale: 600)
            let timeRange = CMTimeRangeMake(start: start, duration: duration)

            let segMuted = segment.audioMuted ?? false
            let segVolume = segMuted ? Float(0.0) : Float(segment.volume ?? Double(globalVolume))
            params.setVolumeRamp(fromStartVolume: segVolume, toEndVolume: segVolume, timeRange: timeRange)
        }
    }

}
