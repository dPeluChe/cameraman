//
//  ThumbnailCacheTypes.swift
//  EngineKit
//
//  Extracted from ThumbnailCache.swift — types, configuration, and errors
//

import Foundation
import CoreGraphics
import ImageIO

extension ThumbnailCache {
    /// Cache configuration
    public struct Configuration: Sendable {
        public let maxThumbnailCount: Int
        public let thumbnailWidth: Int
        public let thumbnailHeight: Int
        public let enableWaveformCache: Bool
        public let waveformResolution: Int
        public let enableDiskCache: Bool

        public init(
            maxThumbnailCount: Int = 100,
            thumbnailWidth: Int = 160,
            thumbnailHeight: Int = 90,
            enableWaveformCache: Bool = true,
            waveformResolution: Int = 1000,
            enableDiskCache: Bool = true
        ) {
            self.maxThumbnailCount = maxThumbnailCount
            self.thumbnailWidth = thumbnailWidth
            self.thumbnailHeight = thumbnailHeight
            self.enableWaveformCache = enableWaveformCache
            self.waveformResolution = waveformResolution
            self.enableDiskCache = enableDiskCache
        }

        public static let `default` = Configuration()

        public static let highQuality = Configuration(
            maxThumbnailCount: 200,
            thumbnailWidth: 320,
            thumbnailHeight: 180,
            enableWaveformCache: true,
            waveformResolution: 2000,
            enableDiskCache: true
        )

        public static let lowMemory = Configuration(
            maxThumbnailCount: 50,
            thumbnailWidth: 120,
            thumbnailHeight: 68,
            enableWaveformCache: false,
            waveformResolution: 500,
            enableDiskCache: false
        )
    }

    /// Cached thumbnail data
    public struct CachedThumbnail: Sendable {
        public let time: TimeInterval
        public let imageData: Data
        public let width: Int
        public let height: Int
        public let cachedAt: Date

        public init(time: TimeInterval, imageData: Data, width: Int, height: Int) {
            self.time = time
            self.imageData = imageData
            self.width = width
            self.height = height
            self.cachedAt = Date()
        }
    }

    /// Cached waveform data
    public struct CachedWaveform: Sendable {
        public let samples: [Float]
        public let duration: TimeInterval
        public let sampleRate: Double
        public let cachedAt: Date

        public init(samples: [Float], duration: TimeInterval, sampleRate: Double) {
            self.samples = samples
            self.duration = duration
            self.sampleRate = sampleRate
            self.cachedAt = Date()
        }
    }

    /// Cache error types
    public enum CacheError: Error, Equatable, Sendable {
        case projectNotSet
        case mediaFileNotFound(String)
        case thumbnailGenerationFailed(String)
        case waveformGenerationFailed(String)
        case cacheDirectoryNotAccessible
        case insufficientMemory

        public var localizedDescription: String {
            switch self {
            case .projectNotSet:
                return "Project not set for cache"
            case .mediaFileNotFound(let path):
                return "Media file not found: \(path)"
            case .thumbnailGenerationFailed(let reason):
                return "Thumbnail generation failed: \(reason)"
            case .waveformGenerationFailed(let reason):
                return "Waveform generation failed: \(reason)"
            case .cacheDirectoryNotAccessible:
                return "Cache directory is not accessible"
            case .insufficientMemory:
                return "Insufficient memory for cache operation"
            }
        }
    }
}

// MARK: - CGImage Extension

extension CGImage {
    /// Convert CGImage to PNG data
    func pngData() throws -> Data {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                mutableData,
                "public.png" as CFString,
                1,
                nil
              ) else {
            throw ThumbnailCache.CacheError.thumbnailGenerationFailed("Failed to create PNG data")
        }

        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailCache.CacheError.thumbnailGenerationFailed("Failed to finalize PNG data")
        }

        return mutableData as Data
    }
}
