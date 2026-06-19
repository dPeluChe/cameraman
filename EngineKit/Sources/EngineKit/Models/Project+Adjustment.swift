//
//  Project+Adjustment.swift
//  EngineKit
//
//  Extensible per-clip / per-layer adjustment ("effect") model.
//
//  An `Adjustment` is a non-destructive effect attached to a `TimelineClip`.
//  Each adjustment carries:
//    - a `kind` (sepia, monochrome, brightness, audioPitch, …) — an open string
//      type so new effects can be added without a schema migration,
//    - a `target` layer (frame / screen / camera / background / audio) so the
//      same recording clip can, e.g., sepia the camera while the background goes
//      black & white,
//    - a `parameters` bag (effect-specific scalars like intensity / radius),
//    - an optional clip-relative time window (`start`/`end`).
//
//  Visual adjustments are rendered by `AdjustmentRenderer` inside
//  `MaskedVideoCompositor`; audio adjustments are applied by `AudioMixBuilder`
//  via an `MTAudioProcessingTap`. Both preview and export share this pipeline.
//

import Foundation

// MARK: - Adjustment

extension Project {

    /// A non-destructive effect attached to a timeline clip.
    public struct Adjustment: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        /// What kind of effect this is (open/extensible — see `AdjustmentKind`).
        public var kind: AdjustmentKind
        /// Which layer of the clip the effect applies to.
        public var target: AdjustmentTarget
        /// Effect-specific scalar parameters (e.g. `["intensity": 0.8]`).
        public var parameters: [String: Double]
        /// Whether the effect is currently active.
        public var enabled: Bool
        /// Clip-relative start (seconds). `nil` = from the clip's start.
        public var start: TimeInterval?
        /// Clip-relative end (seconds). `nil` = to the clip's end.
        public var end: TimeInterval?

        public init(
            id: UUID = UUID(),
            kind: AdjustmentKind,
            target: AdjustmentTarget = .frame,
            parameters: [String: Double] = [:],
            enabled: Bool = true,
            start: TimeInterval? = nil,
            end: TimeInterval? = nil
        ) {
            self.id = id
            self.kind = kind
            self.target = target
            self.parameters = parameters
            self.enabled = enabled
            self.start = start
            self.end = end
        }
    }

    /// The layer an adjustment targets within a clip's composited output.
    public enum AdjustmentTarget: String, Codable, Sendable, CaseIterable {
        /// The whole composited frame for the clip's time range (everything).
        case frame
        /// The screen recording layer (or static image/color content).
        case screen
        /// The camera (PiP) layer.
        case camera
        /// The background layer behind the screen.
        case background
        /// The clip's audio (mic + system for recordings, the file for audio clips).
        case audio
    }

    /// Open string-backed effect identifier. Built-in kinds are provided as
    /// static members, but any `rawValue` is valid so the renderer can be
    /// extended (or driven from config) without a model change.
    public struct AdjustmentKind: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        // Encode/decode as a bare JSON string ("sepia") rather than {"rawValue":…}.
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.rawValue = try container.decode(String.self)
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        // MARK: Built-in video kinds
        /// Warm, aged photo tone. Params: `intensity` (0–1, default 1).
        public static let sepia = AdjustmentKind(rawValue: "sepia")
        /// Black & white (full desaturation). No params.
        public static let monochrome = AdjustmentKind(rawValue: "monochrome")
        /// Brightness offset. Params: `brightness` (-1…1, default 0).
        public static let brightness = AdjustmentKind(rawValue: "brightness")
        /// Contrast multiplier. Params: `contrast` (0…4, default 1).
        public static let contrast = AdjustmentKind(rawValue: "contrast")
        /// Saturation multiplier. Params: `saturation` (0…2, default 1).
        public static let saturation = AdjustmentKind(rawValue: "saturation")
        /// Combined brightness/contrast/saturation in one pass (CIColorControls).
        public static let colorControls = AdjustmentKind(rawValue: "colorControls")
        /// Vibrance (saturation of muted colors). Params: `amount` (-1…1).
        public static let vibrance = AdjustmentKind(rawValue: "vibrance")
        /// Hue rotation. Params: `angle` (radians).
        public static let hue = AdjustmentKind(rawValue: "hue")
        /// Invert colors. No params.
        public static let invert = AdjustmentKind(rawValue: "invert")
        /// Darkened edges. Params: `intensity` (0…1), `radius` (0…2).
        public static let vignette = AdjustmentKind(rawValue: "vignette")
        /// Gaussian blur. Params: `radius` (px).
        public static let gaussianBlur = AdjustmentKind(rawValue: "gaussianBlur")

        // MARK: Built-in audio kinds
        /// Pitch shift (voice deeper/higher). Params: `cents` (-2400…2400) or `semitones`.
        public static let audioPitch = AdjustmentKind(rawValue: "audioPitch")
        /// Linear gain. Params: `gain` (multiplier, 0…4).
        public static let audioGain = AdjustmentKind(rawValue: "audioGain")

        /// Every built-in kind — single source of truth for UI catalogs and MCP
        /// validation. Add new kinds here so all callers stay in sync.
        public static let allBuiltIn: [AdjustmentKind] = [
            .sepia, .monochrome, .brightness, .contrast, .saturation, .colorControls,
            .vibrance, .hue, .invert, .vignette, .gaussianBlur, .audioPitch, .audioGain
        ]

        /// Whether this kind is an audio effect (routed to the audio pipeline).
        public var isAudio: Bool {
            rawValue.hasPrefix("audio")
        }
    }
}

// MARK: - Serializable config for the compositor / audio pipeline

/// A flattened, render-ready adjustment with an *absolute* timeline window.
/// Built once per render (see `Project.adjustmentConfigs`) and carried on the
/// compositor instruction, then filtered per-frame — mirroring how
/// `OverlayConfig` and the zoom plan are passed down.
public struct AdjustmentConfig: Sendable, Equatable {
    public let kind: String
    public let target: Project.AdjustmentTarget
    public let parameters: [String: Double]
    /// Absolute timeline start (seconds).
    public let start: TimeInterval
    /// Absolute timeline end (seconds).
    public let end: TimeInterval

    public init(
        kind: String,
        target: Project.AdjustmentTarget,
        parameters: [String: Double],
        start: TimeInterval,
        end: TimeInterval
    ) {
        self.kind = kind
        self.target = target
        self.parameters = parameters
        self.start = start
        self.end = end
    }

    /// Whether this adjustment is active at the given absolute timeline time.
    public func isActive(at time: TimeInterval) -> Bool {
        time >= start && time <= end
    }
}

/// A flattened audio adjustment with an absolute-timeline window and the audio
/// lane it applies to. Built by `Project.audioAdjustmentSpecs`.
public struct AudioAdjustmentSpec: Sendable, Equatable {
    /// Which composition audio track this affects.
    public enum Lane: Sendable, Equatable {
        case mic
        case system
        case clip(String)
    }

    public let lane: Lane
    public let kind: String
    public let parameters: [String: Double]
    public let start: TimeInterval
    public let end: TimeInterval

    public init(lane: Lane, kind: String, parameters: [String: Double], start: TimeInterval, end: TimeInterval) {
        self.lane = lane
        self.kind = kind
        self.parameters = parameters
        self.start = start
        self.end = end
    }
}

// MARK: - Project flattening

extension Project {

    /// All enabled *visual* adjustments, flattened to absolute-timeline windows.
    ///
    /// Covers recording clips (screen/camera/background/frame layers) and static
    /// image/color clips (rendered as the screen layer). Imported `.video` clip
    /// effects are applied via their `VideoOverlaySource` and `.audio` clips have
    /// no visual layer, so both are excluded here.
    public var adjustmentConfigs: [AdjustmentConfig] {
        var result: [AdjustmentConfig] = []
        for track in timeline.tracks {
            for clip in track.clips {
                switch clip.content {
                case .recording, .image, .color:
                    result.append(contentsOf: clip.visualAdjustmentConfigs())
                case .video, .audio:
                    continue
                }
            }
        }
        return result
    }

    /// All enabled *audio* adjustments, flattened with absolute-timeline windows
    /// and the audio lane they apply to. Consumed by `AudioMixBuilder`.
    ///
    /// Recording-clip audio defaults to the mic lane (the voice); pass
    /// `parameters["applyToSystem"] = 1` to also affect system audio. Audio-clip
    /// adjustments target that clip's own lane.
    public var audioAdjustmentSpecs: [AudioAdjustmentSpec] {
        var result: [AudioAdjustmentSpec] = []
        for track in timeline.tracks {
            for clip in track.clips {
                guard let adjustments = clip.adjustments else { continue }
                let clipDuration = clip.duration
                for adj in adjustments where adj.enabled && adj.kind.isAudio {
                    let start = clip.timelineIn + max(0, adj.start ?? 0)
                    let end = clip.timelineIn + min(clipDuration, adj.end ?? clipDuration)
                    let lanes: [AudioAdjustmentSpec.Lane]
                    switch clip.content {
                    case .recording:
                        lanes = (adj.parameters["applyToSystem"] ?? 0) > 0 ? [.mic, .system] : [.mic]
                    case .audio:
                        lanes = [.clip(clip.id)]
                    default:
                        lanes = []
                    }
                    for lane in lanes {
                        result.append(AudioAdjustmentSpec(
                            lane: lane, kind: adj.kind.rawValue,
                            parameters: adj.parameters, start: start, end: end
                        ))
                    }
                }
            }
        }
        return result
    }

    /// Whether the timeline has any real video frames (a recording or an imported
    /// video clip on any track). Static-only projects (image/color cards) have no
    /// frames for AVAssetExportSession to render.
    public var hasRenderableVideo: Bool {
        timeline.tracks.contains { track in
            track.clips.contains { clip in
                switch clip.content {
                case .recording, .video: return true
                case .image, .color, .audio: return false
                }
            }
        }
    }

    /// Whether any clip carries an enabled visual adjustment. Used to force the
    /// custom compositor on render paths that would otherwise use plain layer
    /// instructions.
    public var hasVisualAdjustments: Bool {
        timeline.tracks.contains { track in
            track.clips.contains { clip in
                guard let adjustments = clip.adjustments else { return false }
                switch clip.content {
                case .recording, .image, .color:
                    return adjustments.contains { $0.enabled && !$0.kind.isAudio }
                case .video, .audio:
                    return false
                }
            }
        }
    }
}

extension Project.TimelineClip {

    /// This clip's enabled *visual* adjustments, flattened to absolute-timeline
    /// windows. Shared by `Project.adjustmentConfigs` (recording/image/color
    /// clips) and the imported-video overlay sources so both flatten identically.
    func visualAdjustmentConfigs() -> [AdjustmentConfig] {
        let clipDuration = duration
        return (adjustments ?? [])
            .filter { $0.enabled && !$0.kind.isAudio }
            .map { adj in
                AdjustmentConfig(
                    kind: adj.kind.rawValue,
                    target: adj.target,
                    parameters: adj.parameters,
                    start: timelineIn + max(0, adj.start ?? 0),
                    end: timelineIn + min(clipDuration, adj.end ?? clipDuration)
                )
            }
    }
}
