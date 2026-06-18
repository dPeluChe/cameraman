//
//  AudioMixBuilder.swift
//  EngineKit
//
//  Builds AVMutableAudioMix for per-track mute/volume control.
//  Used by both Preview and Export pipelines.
//  Updated for multi-track timeline with audio clip tracks.
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
        segments: [Project.Timeline.Segment] = [],
        audioAdjustments: [AudioAdjustmentSpec] = []
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
            applyPitch(to: params, specs: audioAdjustments.filter { $0.lane == .system })
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
            applyPitch(to: params, specs: audioAdjustments.filter { $0.lane == .mic })
            parameters.append(params)
        }

        // Legacy media items audio
        for additional in compositionResult.additionalAudioTracks {
            let params = AVMutableAudioMixInputParameters(track: additional.track)
            let volume = additional.mediaItem.isMuted ? Float(0.0) : Float(additional.mediaItem.volume)
            params.setVolume(volume, at: .zero)
            parameters.append(params)
        }

        // Audio clips from timeline tracks
        for audioClip in compositionResult.audioClipTracks {
            let params = AVMutableAudioMixInputParameters(track: audioClip.track)
            let clipVolume = audioClip.clip.volume ?? 1.0
            params.setVolume(Float(clipVolume), at: .zero)
            applyPitch(to: params, specs: audioAdjustments.filter { $0.lane == .clip(audioClip.clip.id) })
            parameters.append(params)
        }

        // Embedded audio from imported video clips
        for videoClipAudio in compositionResult.videoClipAudioTracks {
            let params = AVMutableAudioMixInputParameters(track: videoClipAudio.track)
            let clipVolume = videoClipAudio.clip.volume ?? 1.0
            params.setVolume(Float(clipVolume), at: .zero)
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

    /// Attach a pitch-shift processing tap if any pitch spec targets this track.
    /// Pitch is applied to the whole track (time-windowed pitch is a future
    /// enhancement); non-pitch audio kinds are handled via volume controls.
    /// `cents` is taken directly, or derived from `semitones` (×100).
    private static func applyPitch(to params: AVMutableAudioMixInputParameters, specs: [AudioAdjustmentSpec]) {
        let pitchSpecs = specs.filter { $0.kind == Project.AdjustmentKind.audioPitch.rawValue }
        guard let spec = pitchSpecs.first else { return }
        let cents: Double
        if let c = spec.parameters["cents"] {
            cents = c
        } else if let semitones = spec.parameters["semitones"] {
            cents = semitones * 100
        } else {
            return
        }
        guard abs(cents) > 0.5, let tap = AudioAdjustmentTap.makePitchTap(cents: Float(cents)) else { return }
        params.audioTapProcessor = tap
    }

}
