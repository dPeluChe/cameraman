//
//  AIModels.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// AI suggestion for improving a video project
public struct Suggestion: Codable, Identifiable {
    /// Unique identifier
    public let id: UUID
    /// Type of suggestion
    public let type: SuggestionType
    /// Human-readable title
    public let title: String
    /// Detailed description
    public let description: String
    /// Confidence score (0.0 - 1.0)
    public let confidence: Double
    /// Start time on timeline (seconds)
    public let timelineIn: TimeInterval
    /// End time on timeline (seconds)
    public let timelineOut: TimeInterval
    /// Additional metadata
    public let metadata: [String: AIAnyCodable]

    public init(
        id: UUID,
        type: SuggestionType,
        title: String,
        description: String,
        confidence: Double,
        timelineIn: TimeInterval,
        timelineOut: TimeInterval,
        metadata: [String: Any] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.confidence = confidence
        self.timelineIn = timelineIn
        self.timelineOut = timelineOut
        self.metadata = metadata.mapValues { AIAnyCodable($0) }
    }

    /// Helper to get metadata value
    public func metadata<T>(_ key: String, as type: T.Type) -> T? {
        metadata[key]?.value as? T
    }

    /// Coding keys to handle AnyCodable metadata
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case description
        case confidence
        case timelineIn
        case timelineOut
        case metadata
    }
}

/// Type of AI suggestion
public enum SuggestionType: String, Codable {
    /// Remove silent section
    case removeSilence
    /// Create chapter marker
    case createChapter
    /// Suggest cut point
    case suggestCut
    /// Suggest overlay addition
    case suggestOverlay
    /// Suggest zoom application
    case suggestZoom
    /// Suggest background change
    case suggestBackground
}

/// Reference to an AI-generated or external asset
public struct AssetRef: Codable, Equatable {
    /// Unique identifier
    public let id: UUID
    /// Asset type
    public let type: AssetType
    /// Asset filename
    public let filename: String
    /// Asset data (for local storage)
    public let data: Data
    /// URL (if cloud-hosted)
    public let url: URL?
    /// Thumbnail data (optional)
    public let thumbnail: Data?
    /// Metadata
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        type: AssetType,
        filename: String,
        data: Data,
        url: URL? = nil,
        thumbnail: Data? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.filename = filename
        self.data = data
        self.url = url
        self.thumbnail = thumbnail
        self.metadata = metadata
    }

    /// Create AssetRef from local file
    public static func from(fileAt path: URL, type: AssetType) throws -> AssetRef {
        let data = try Data(contentsOf: path)
        return AssetRef(
            type: type,
            filename: path.lastPathComponent,
            data: data,
            url: nil,
            thumbnail: nil
        )
    }
}

/// Type of asset
public enum AssetType: String, Codable {
    /// Image background
    case image
    /// Video background
    case video
    /// Styled video
    case styledVideo
    /// Processed camera video
    case processedCamera
}

/// Silence detection options
public struct SilenceDetectionOptions: Codable, Equatable {
    /// Silence threshold in dB (lower = more sensitive)
    public let silenceThreshold: Float
    /// Minimum silence duration to detect (seconds)
    public let minSilenceDuration: TimeInterval
    /// Whether to create cut suggestions automatically
    public let autoCreateCuts: Bool

    public init(
        silenceThreshold: Float = -40.0,
        minSilenceDuration: TimeInterval = 1.0,
        autoCreateCuts: Bool = true
    ) {
        self.silenceThreshold = silenceThreshold
        self.minSilenceDuration = minSilenceDuration
        self.autoCreateCuts = autoCreateCuts
    }

    public static let `default` = SilenceDetectionOptions()

    public static let sensitive = SilenceDetectionOptions(
        silenceThreshold: -50.0,
        minSilenceDuration: 0.5
    )

    public static let aggressive = SilenceDetectionOptions(
        silenceThreshold: -30.0,
        minSilenceDuration: 2.0
    )
}

/// Chapter suggestion options
public struct ChapterSuggestionOptions: Codable, Equatable {
    /// Minimum chapter duration (seconds)
    public let minChapterDuration: TimeInterval
    /// Maximum number of chapters to suggest
    public let maxChapters: Int
    /// Whether to use NLP for topic detection
    public let useTopicDetection: Bool

    public init(
        minChapterDuration: TimeInterval = 30.0,
        maxChapters: Int = 20,
        useTopicDetection: Bool = false
    ) {
        self.minChapterDuration = minChapterDuration
        self.maxChapters = maxChapters
        self.useTopicDetection = useTopicDetection
    }

    public static let `default` = ChapterSuggestionOptions()

    public static let shortChapters = ChapterSuggestionOptions(
        minChapterDuration: 15.0,
        maxChapters: 40
    )

    public static let longChapters = ChapterSuggestionOptions(
        minChapterDuration: 60.0,
        maxChapters: 10
    )
}

/// Background generation options
public struct BackgroundGenerationOptions: Codable, Equatable {
    /// Width in pixels
    public let width: Int
    /// Height in pixels
    public let height: Int
    /// Style preset
    public let style: BackgroundStyle

    public init(
        width: Int = 1920,
        height: Int = 1080,
        style: BackgroundStyle = .gradient
    ) {
        self.width = width
        self.height = height
        self.style = style
    }

    public static let `default` = BackgroundGenerationOptions()

    public static let fourK = BackgroundGenerationOptions(
        width: 3840,
        height: 2160
    )

    public static let vertical = BackgroundGenerationOptions(
        width: 1080,
        height: 1920
    )
}

/// Background style
public enum BackgroundStyle: String, Codable {
    case gradient
    case solid
    case pattern
    case abstract
    case minimal
    case professional
    case creative
}

/// Style transfer options
public struct StyleTransferOptions: Codable, Equatable {
    /// Style strength (0.0 - 1.0)
    public let strength: Double
    /// Whether to preserve original colors
    public let preserveColors: Bool
    /// Quality preset
    public let quality: Quality

    public enum Quality: String, Codable {
        case draft
        case normal
        case high
    }

    public init(
        strength: Double = 0.7,
        preserveColors: Bool = true,
        quality: Quality = .normal
    ) {
        self.strength = strength
        self.preserveColors = preserveColors
        self.quality = quality
    }

    public static let `default` = StyleTransferOptions()

    public static let subtle = StyleTransferOptions(strength: 0.3)

    public static let strong = StyleTransferOptions(strength: 0.95)

    public static let highQuality = StyleTransferOptions(quality: .high)
}

/// Background replacement options
public struct BackgroundReplacementOptions: Codable, Equatable {
    /// Edge smoothness (0.0 - 1.0)
    public let edgeSmoothness: Double
    /// Whether to apply lighting adjustment
    public let adjustLighting: Bool
    /// Quality preset
    public let quality: Quality

    public enum Quality: String, Codable {
        case draft
        case normal
        case high
    }

    public init(
        edgeSmoothness: Double = 0.5,
        adjustLighting: Bool = true,
        quality: Quality = .normal
    ) {
        self.edgeSmoothness = edgeSmoothness
        self.adjustLighting = adjustLighting
        self.quality = quality
    }

    public static let `default` = BackgroundReplacementOptions()

    public static let highQuality = BackgroundReplacementOptions(quality: .high)

    public static let smooth = BackgroundReplacementOptions(edgeSmoothness: 0.8)
}

// MARK: - AI Provider Protocol

/// AI provider for cloud-based AI operations
public protocol AIProvider {
    /// Generate a background image
    func generateBackground(
        prompt: String,
        width: Int,
        height: Int,
        style: BackgroundStyle
    ) async throws -> AssetRef

    /// Apply style transfer to video
    func applyStyleTransfer(
        projectId: ProjectId,
        style: String,
        strength: Double
    ) async throws -> AssetRef

    /// Replace background in camera track
    func replaceCameraBackground(
        projectId: ProjectId,
        background: AssetRef,
        edgeSmoothness: Double
    ) async throws -> AssetRef
}

// MARK: - Errors

/// AI service errors
public enum AIServiceError: Error, LocalizedError {
    case noAudioTrack
    case transcriptNotFound
    case noProviderConfigured
    case audioAnalysisFailed(String)
    case providerError(String)
    case invalidAsset
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in project"
        case .transcriptNotFound:
            return "Transcript not found. Please run transcription first."
        case .noProviderConfigured:
            return "No AI provider configured"
        case .audioAnalysisFailed(let message):
            return "Audio analysis failed: \(message)"
        case .providerError(let message):
            return "Provider error: \(message)"
        case .invalidAsset:
            return "Invalid asset reference"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        }
    }
}

// MARK: - AIAnyCodable Helper

/// Helper type for encoding/decoding Any values in AI metadata
public struct AIAnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AIAnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AIAnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AIAnyCodable value cannot be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AIAnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AIAnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AIAnyCodable value cannot be encoded"
                )
            )
        }
    }
}
