//
//  ExportPresets.swift
//  EngineKit
//
//  Extracted from ExportEngine.swift
//

import Foundation

// MARK: - Export Preset

/// Export preset configuration
public struct ExportPreset: Equatable, Hashable, Sendable {
    /// Preset identifier
    public let id: String
    /// Human-readable name
    public let name: String
    /// Output configuration
    public let output: OutputConfiguration
    /// Export options
    public let options: PresetOptions

    /// Output configuration
    public struct OutputConfiguration: Equatable, Hashable, Sendable {
        public let width: Int
        public let height: Int
        public let fps: Int
        public let codec: String
        public let bitrateMbps: Double
        public let audioBitrateKbps: Int
    }

    /// Preset options
    public struct PresetOptions: Equatable, Hashable, Sendable {
        public let burnCaptions: Bool
        public let includeCursorHighlight: Bool
    }

    /// Web 1080p H.264 preset (default)
    public static let web1080h264 = ExportPreset(
        id: "web_1080_h264",
        name: "Web 1080p (H.264)",
        output: OutputConfiguration(
            width: 1920,
            height: 1080,
            fps: 60,
            codec: "h264",
            bitrateMbps: 8.0,
            audioBitrateKbps: 192
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: true
        )
    )

    /// High-quality 1080p HEVC preset
    public static let high1080hevc = ExportPreset(
        id: "high_1080_hevc",
        name: "High 1080p (HEVC)",
        output: OutputConfiguration(
            width: 1920,
            height: 1080,
            fps: 60,
            codec: "hevc",
            bitrateMbps: 12.0,
            audioBitrateKbps: 192
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: true
        )
    )

    /// Portrait 9:16 1080p H.264 preset
    public static let portrait1080h264 = ExportPreset(
        id: "portrait_1080_h264",
        name: "Portrait 1080p (H.264)",
        output: OutputConfiguration(
            width: 1080,
            height: 1920,
            fps: 60,
            codec: "h264",
            bitrateMbps: 8.0,
            audioBitrateKbps: 192
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: true
        )
    )

    /// 4K HEVC preset (high quality, smaller file than H.264 at same quality)
    public static let ultra4kHevc = ExportPreset(
        id: "ultra_4k_hevc",
        name: "4K (HEVC)",
        output: OutputConfiguration(
            width: 3840,
            height: 2160,
            fps: 60,
            codec: "hevc",
            bitrateMbps: 30.0,
            audioBitrateKbps: 256
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: true
        )
    )

    /// Animated GIF preset (for short clips and social media)
    public static let animatedGIF = ExportPreset(
        id: "animated_gif",
        name: "Animated GIF",
        output: OutputConfiguration(
            width: 800,
            height: 600,
            fps: 15,
            codec: "gif",
            bitrateMbps: 0,
            audioBitrateKbps: 0
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: false
        )
    )
}

// MARK: - Export Options

/// Additional export options
public struct ExportOptions: Equatable, Sendable {
    /// Whether to burn captions into the video
    public let burnCaptions: Bool
    /// Whether to include cursor highlight overlay
    public let includeCursorHighlight: Bool
    /// Custom output filename (optional)
    public let outputFilename: String?
    /// GIF-specific options (for animated GIF exports)
    public let gifOptions: GIFExportOptions?
    /// Whether to apply zoom during export
    public let applyZoom: Bool
    /// Zoom plan to use for export (optional, will be loaded from project if not provided)
    public let zoomPlan: ZoomPlanGenerator.ZoomPlan?
    /// Cursor plan to use for synthetic cursor rendering during export.
    /// `nil` means no synthetic cursor regardless of project settings.
    public let cursorPlan: CursorPlan?
    /// Audio mute state for per-track mute/volume during export
    public let audioMuteState: AudioMixBuilder.TrackMuteState?
    /// Video mute state for hiding screen/camera during export
    public let videoMuteState: VideoMuteState?
    /// Scales the preset's target bitrate: 0.6 = smaller file, 1.5 = higher quality
    public let qualityMultiplier: Double
    /// Whether to add Cameraman's promotional badge to the final render.
    public let includeCameramanWatermark: Bool

    public init(
        burnCaptions: Bool = false,
        includeCursorHighlight: Bool = true,
        outputFilename: String? = nil,
        gifOptions: GIFExportOptions? = nil,
        applyZoom: Bool = true,
        zoomPlan: ZoomPlanGenerator.ZoomPlan? = nil,
        cursorPlan: CursorPlan? = nil,
        audioMuteState: AudioMixBuilder.TrackMuteState? = nil,
        videoMuteState: VideoMuteState? = nil,
        qualityMultiplier: Double = 1.0,
        includeCameramanWatermark: Bool = false
    ) {
        self.burnCaptions = burnCaptions
        self.includeCursorHighlight = includeCursorHighlight
        self.outputFilename = outputFilename
        self.gifOptions = gifOptions
        self.applyZoom = applyZoom
        self.zoomPlan = zoomPlan
        self.cursorPlan = cursorPlan
        self.audioMuteState = audioMuteState
        self.videoMuteState = videoMuteState
        self.qualityMultiplier = qualityMultiplier
        self.includeCameramanWatermark = includeCameramanWatermark
    }

    public static let `default` = ExportOptions()

    /// Export options with zoom disabled
    public static let noZoom = ExportOptions(applyZoom: false)
}

extension ExportPreset {
    /// Target output size in bytes for a given duration: (video + audio bitrate)
    /// scaled by the quality multiplier, with 5% container overhead.
    public func targetFileSizeBytes(duration: TimeInterval, qualityMultiplier: Double = 1.0) -> Int64 {
        let videoBitsPerSecond = output.bitrateMbps * 1_000_000 * qualityMultiplier
        let audioBitsPerSecond = Double(output.audioBitrateKbps) * 1_000
        let totalBits = (videoBitsPerSecond + audioBitsPerSecond) * duration * 1.05
        return Int64(totalBits / 8)
    }

    /// Human-readable estimate ("~120 MB") for the UI; nil when the preset has
    /// no target bitrate (GIF).
    public func estimatedSizeText(duration: TimeInterval, qualityMultiplier: Double = 1.0) -> String? {
        guard output.bitrateMbps > 0, duration > 0 else { return nil }
        let bytes = targetFileSizeBytes(duration: duration, qualityMultiplier: qualityMultiplier)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "~" + formatter.string(fromByteCount: bytes)
    }
}

/// Video track mute state for export
public struct VideoMuteState: Equatable, Sendable {
    public let screenMuted: Bool
    public let cameraMuted: Bool

    public init(screenMuted: Bool = false, cameraMuted: Bool = false) {
        self.screenMuted = screenMuted
        self.cameraMuted = cameraMuted
    }
}

// MARK: - GIF Export Options

/// Options specific to GIF export
public struct GIFExportOptions: Equatable, Sendable {
    /// Quality of the GIF (0.0 - 1.0, higher is better)
    public let quality: Double
    /// Number of times to loop the GIF (0 = infinite)
    public let loopCount: Int
    /// Maximum width/height (maintains aspect ratio)
    public let maxSize: Int?
    /// Frame rate for the GIF (overrides preset if specified)
    public let frameRate: Int?
    /// Whether to dither the GIF for better quality
    public let dither: Bool

    public init(
        quality: Double = 0.8,
        loopCount: Int = 0,
        maxSize: Int? = nil,
        frameRate: Int? = nil,
        dither: Bool = true
    ) {
        self.quality = max(0.0, min(1.0, quality))
        self.loopCount = max(0, loopCount)
        self.maxSize = maxSize
        self.frameRate = frameRate
        self.dither = dither
    }

    public static let `default` = GIFExportOptions()

    /// High-quality GIF options (larger file size)
    public static let highQuality = GIFExportOptions(
        quality: 0.95,
        loopCount: 0,
        maxSize: nil,
        frameRate: nil,
        dither: true
    )

    /// Low-quality GIF options (smaller file size)
    public static let lowQuality = GIFExportOptions(
        quality: 0.5,
        loopCount: 0,
        maxSize: 600,
        frameRate: 10,
        dither: false
    )
}
