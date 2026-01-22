//
//  ThumbnailCache.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19
//

import Foundation
import AVFoundation
import CoreGraphics

/// Cache for thumbnails and waveforms to improve UX performance
/// Stores generated thumbnails and waveforms in project cache directory
public actor ThumbnailCache {
    /// Cache configuration
    public struct Configuration: Sendable {
        /// Maximum number of thumbnails to cache per project
        public let maxThumbnailCount: Int
        /// Thumbnail width in pixels
        public let thumbnailWidth: Int
        /// Thumbnail height in pixels
        public let thumbnailHeight: Int
        /// Whether to enable waveform caching
        public let enableWaveformCache: Bool
        /// Waveform resolution (number of samples)
        public let waveformResolution: Int
        /// Whether to enable disk caching (persistent cache)
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

        /// Default configuration
        public static let `default` = Configuration()

        /// High-quality configuration (more thumbnails, higher resolution)
        public static let highQuality = Configuration(
            maxThumbnailCount: 200,
            thumbnailWidth: 320,
            thumbnailHeight: 180,
            enableWaveformCache: true,
            waveformResolution: 2000,
            enableDiskCache: true
        )

        /// Low-memory configuration (fewer thumbnails, lower resolution)
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
        /// Time position of the thumbnail (seconds)
        public let time: TimeInterval
        /// Thumbnail image data (PNG compressed)
        public let imageData: Data
        /// Thumbnail width
        public let width: Int
        /// Thumbnail height
        public let height: Int
        /// Cache timestamp
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
        /// Waveform samples (normalized -1.0 to 1.0)
        public let samples: [Float]
        /// Audio duration (seconds)
        public let duration: TimeInterval
        /// Sample rate (samples per second)
        public let sampleRate: Double
        /// Cache timestamp
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

    // MARK: - Properties

    /// Current project
    private var project: Project?

    /// Project directory path
    private var projectDirectory: String?

    /// Cache configuration
    private let configuration: Configuration

    /// In-memory thumbnail cache (time -> CachedThumbnail)
    private var thumbnailCache: [TimeInterval: CachedThumbnail] = [:]

    /// In-memory waveform cache (track path -> CachedWaveform)
    private var waveformCache: [String: CachedWaveform] = [:]

    /// Cache directory path
    private var cacheDirectory: String? {
        guard let projectDir = projectDirectory else {
            return nil
        }
        return (projectDir as NSString).appendingPathComponent("cache/thumbnails")
    }

    /// Waveform cache directory path
    private var waveformCacheDirectory: String? {
        guard let projectDir = projectDirectory else {
            return nil
        }
        return (projectDir as NSString).appendingPathComponent("cache/waveforms")
    }

    // MARK: - Initialization

    /// Initialize with configuration
    /// - Parameter configuration: Cache configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Set the current project
    /// - Parameters:
    ///   - project: Project to cache for
    ///   - projectDirectory: Project directory path
    public func setProject(_ project: Project, projectDirectory: String) {
        self.project = project
        self.projectDirectory = projectDirectory

        // Clear in-memory caches when project changes
        thumbnailCache.removeAll()
        waveformCache.removeAll()

        // Create cache directories if needed
        if configuration.enableDiskCache {
            createCacheDirectories()
        }
    }

    /// Clear the current project
    public func clearProject() {
        self.project = nil
        self.projectDirectory = nil
        thumbnailCache.removeAll()
        waveformCache.removeAll()
    }

    // MARK: - Thumbnail Caching

    /// Get thumbnails for a time range
    /// - Parameters:
    ///   - count: Number of thumbnails to return
    ///   - startTime: Start time of range
    ///   - endTime: End time of range
    /// - Returns: Array of CachedThumbnail objects
    /// - Throws: CacheError if generation fails
    public func getThumbnails(
        count: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> [CachedThumbnail] {
        guard let project = project else {
            throw CacheError.projectNotSet
        }

        let duration = endTime - startTime
        let interval = duration / Double(max(count - 1, 1))

        var thumbnails: [CachedThumbnail] = []

        for i in 0..<count {
            let time = startTime + (Double(i) * interval)

            // Check in-memory cache first
            if let cached = thumbnailCache[time] {
                thumbnails.append(cached)
                continue
            }

            // Check disk cache if enabled
            if configuration.enableDiskCache,
               let diskCached = try? loadThumbnailFromDisk(at: time) {
                thumbnails.append(diskCached)
                thumbnailCache[time] = diskCached
                continue
            }

            // Generate new thumbnail
            let thumbnail = try await generateThumbnail(at: time, for: project)
            thumbnails.append(thumbnail)

            // Cache in memory
            thumbnailCache[time] = thumbnail

            // Cache to disk if enabled
            if configuration.enableDiskCache {
                try? saveThumbnailToDisk(thumbnail, at: time)
            }
        }

        return thumbnails
    }

    /// Get a single thumbnail at a specific time
    /// - Parameter time: Time position in seconds
    /// - Returns: CachedThumbnail object
    /// - Throws: CacheError if generation fails
    public func getThumbnail(at time: TimeInterval) async throws -> CachedThumbnail {
        guard let project = project else {
            throw CacheError.projectNotSet
        }

        // Check in-memory cache first
        if let cached = thumbnailCache[time] {
            return cached
        }

        // Check disk cache if enabled
        if configuration.enableDiskCache,
           let diskCached = try? loadThumbnailFromDisk(at: time) {
            thumbnailCache[time] = diskCached
            return diskCached
        }

        // Generate new thumbnail
        let thumbnail = try await generateThumbnail(at: time, for: project)

        // Cache in memory
        thumbnailCache[time] = thumbnail

        // Cache to disk if enabled
        if configuration.enableDiskCache {
            try? saveThumbnailToDisk(thumbnail, at: time)
        }

        return thumbnail
    }

    /// Pre-generate thumbnails for the entire project
    /// - Parameter progress: Optional progress handler (0.0 to 1.0)
    /// - Returns: Number of thumbnails generated
    /// - Throws: CacheError if generation fails
    public func generateAllThumbnails(progress: ((Double) -> Void)? = nil) async throws -> Int {
        guard let project = project else {
            throw CacheError.projectNotSet
        }

        let duration = project.timeline.duration
        let thumbnailCount = min(configuration.maxThumbnailCount, Int(duration) + 1)
        let interval = duration / Double(max(thumbnailCount - 1, 1))

        var generatedCount = 0

        for i in 0..<thumbnailCount {
            let time = Double(i) * interval

            // Check if already cached
            if thumbnailCache[time] != nil {
                generatedCount += 1
                continue
            }

            if configuration.enableDiskCache {
                if (try? loadThumbnailFromDisk(at: time)) != nil {
                    generatedCount += 1
                    continue
                }
            }

            // Generate thumbnail
            let thumbnail = try await generateThumbnail(at: time, for: project)
            thumbnailCache[time] = thumbnail

            if configuration.enableDiskCache {
                try? saveThumbnailToDisk(thumbnail, at: time)
            }

            generatedCount += 1

            // Report progress
            let progressValue = Double(i + 1) / Double(thumbnailCount)
            progress?(progressValue)
        }

        return generatedCount
    }

    /// Clear all thumbnails from cache
    public func clearThumbnails() {
        thumbnailCache.removeAll()

        if configuration.enableDiskCache,
           let cacheDir = cacheDirectory {
            try? FileManager.default.removeItem(atPath: cacheDir)
            createCacheDirectories()
        }
    }

    // MARK: - Waveform Caching

    /// Get waveform for an audio track
    /// - Parameter trackPath: Path to audio file
    /// - Returns: CachedWaveform object
    /// - Throws: CacheError if generation fails
    public func getWaveform(for trackPath: String) async throws -> CachedWaveform {
        guard configuration.enableWaveformCache else {
            throw CacheError.waveformGenerationFailed("Waveform caching is disabled")
        }

        // Check in-memory cache first
        if let cached = waveformCache[trackPath] {
            return cached
        }

        // Check disk cache if enabled
        if configuration.enableDiskCache,
           let diskCached = try? loadWaveformFromDisk(for: trackPath) {
            waveformCache[trackPath] = diskCached
            return diskCached
        }

        // Generate new waveform
        let waveform = try await generateWaveform(for: trackPath)

        // Cache in memory
        waveformCache[trackPath] = waveform

        // Cache to disk if enabled
        if configuration.enableDiskCache {
            try? saveWaveformToDisk(waveform, for: trackPath)
        }

        return waveform
    }

    /// Pre-generate waveforms for all audio tracks in the project
    /// - Parameter progress: Optional progress handler (0.0 to 1.0)
    /// - Returns: Number of waveforms generated
    /// - Throws: CacheError if generation fails
    public func generateAllWaveforms(progress: ((Double) -> Void)? = nil) async throws -> Int {
        guard let project = project else {
            throw CacheError.projectNotSet
        }

        guard configuration.enableWaveformCache else {
            return 0
        }
        
        guard let sources = project.primarySources else {
            return 0
        }

        var trackPaths: [String] = []

        // Add system audio track
        if let audio = sources.audio, let systemAudio = audio.system {
            trackPaths.append(systemAudio.path)
        }

        // Add mic audio track
        if let audio = sources.audio, let micAudio = audio.mic {
            trackPaths.append(micAudio.path)
        }

        var generatedCount = 0
        let totalTracks = trackPaths.count

        for (index, trackPath) in trackPaths.enumerated() {
            // Check if already cached
            if waveformCache[trackPath] != nil {
                generatedCount += 1
                continue
            }

            if configuration.enableDiskCache {
                if (try? loadWaveformFromDisk(for: trackPath)) != nil {
                    generatedCount += 1
                    continue
                }
            }

            // Generate waveform
            let waveform = try await generateWaveform(for: trackPath)
            waveformCache[trackPath] = waveform

            if configuration.enableDiskCache {
                try? saveWaveformToDisk(waveform, for: trackPath)
            }

            generatedCount += 1

            // Report progress
            let progressValue = Double(index + 1) / Double(totalTracks)
            progress?(progressValue)
        }

        return generatedCount
    }

    /// Clear all waveforms from cache
    public func clearWaveforms() {
        waveformCache.removeAll()

        if configuration.enableDiskCache,
           let cacheDir = waveformCacheDirectory {
            try? FileManager.default.removeItem(atPath: cacheDir)
            createCacheDirectories()
        }
    }

    /// Clear all cached data (thumbnails and waveforms)
    public func clearAll() {
        clearThumbnails()
        clearWaveforms()
    }

    // MARK: - Cache Statistics

    /// Get cache statistics
    /// - Returns: Dictionary with cache statistics
    public func getCacheStats() -> [String: Any] {
        var stats: [String: Any] = [:]

        stats["thumbnailCount"] = thumbnailCache.count
        stats["waveformCount"] = waveformCache.count
        stats["maxThumbnailCount"] = configuration.maxThumbnailCount
        stats["thumbnailWidth"] = configuration.thumbnailWidth
        stats["thumbnailHeight"] = configuration.thumbnailHeight
        stats["waveformResolution"] = configuration.waveformResolution
        stats["diskCacheEnabled"] = configuration.enableDiskCache
        stats["waveformCacheEnabled"] = configuration.enableWaveformCache

        // Calculate cache sizes
        var thumbnailMemorySize = 0
        for thumbnail in thumbnailCache.values {
            thumbnailMemorySize += thumbnail.imageData.count
        }
        stats["thumbnailMemoryBytes"] = thumbnailMemorySize

        var waveformMemorySize = 0
        for waveform in waveformCache.values {
            waveformMemorySize += waveform.samples.count * MemoryLayout<Float>.size
        }
        stats["waveformMemoryBytes"] = waveformMemorySize

        return stats
    }

    // MARK: - Private Helpers

    /// Generate a thumbnail at a specific time
    private func generateThumbnail(at time: TimeInterval, for project: Project) async throws -> CachedThumbnail {
        guard let sources = project.primarySources else {
            throw CacheError.mediaFileNotFound("No sources found")
        }
        
        let screenPath = sources.screen.path

        // Check if file exists
        guard FileManager.default.fileExists(atPath: screenPath) else {
            throw CacheError.mediaFileNotFound(screenPath)
        }

        let asset = AVAsset(url: URL(fileURLWithPath: screenPath))
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CoreFoundation.CGSize(
            width: configuration.thumbnailWidth,
            height: configuration.thumbnailHeight
        )

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: cmTime, actualTime: nil)

            // Convert CGImage to PNG data
            let imageData = try cgImage.pngData()

            return CachedThumbnail(
                time: time,
                imageData: imageData,
                width: cgImage.width,
                height: cgImage.height
            )
        } catch {
            throw CacheError.thumbnailGenerationFailed(error.localizedDescription)
        }
    }

    /// Generate waveform for an audio track
    private func generateWaveform(for trackPath: String) async throws -> CachedWaveform {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: trackPath) else {
            throw CacheError.mediaFileNotFound(trackPath)
        }

        let asset = AVAsset(url: URL(fileURLWithPath: trackPath))

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            guard let audioTrack = audioTracks.first else {
                throw CacheError.waveformGenerationFailed("No audio track found")
            }

            // Load audio asset
            let duration = try await asset.load(.duration).seconds

            // Read audio samples
            let assetReader = try AVAssetReader(asset: asset)
            let readerOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )

            assetReader.add(readerOutput)
            assetReader.startReading()

            // Read samples and compute RMS for each chunk
            var samples: [Float] = []
            let targetSampleCount = configuration.waveformResolution
            let samplesPerChunk = max(1, Int(duration * 44100) / targetSampleCount)

            var chunkSamples: [Int16] = []
            var chunkIndex = 0

            while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    continue
                }

                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                var totalLength = 0
                let result = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
                length = totalLength

                guard result == noErr,
                      let pointer = dataPointer else {
                    continue
                }

                let int16Pointer = pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { $0 }

                for i in 0..<(length / MemoryLayout<Int16>.size) {
                    chunkSamples.append(int16Pointer[i])

                    if chunkSamples.count >= samplesPerChunk {
                        // Compute RMS for this chunk
                        let sumOfSquares = chunkSamples.reduce(0.0) { $0 + Double($1) * Double($1) }
                        let rms = sqrt(sumOfSquares / Double(chunkSamples.count))
                        let normalized = Float(rms / Double(Int16.max))
                        samples.append(normalized)
                        chunkSamples.removeAll()
                        chunkIndex += 1

                        if samples.count >= targetSampleCount {
                            break
                        }
                    }
                }

                if samples.count >= targetSampleCount {
                    break
                }
            }

            // Handle remaining samples
            if !chunkSamples.isEmpty && samples.count < targetSampleCount {
                let sumOfSquares = chunkSamples.reduce(0.0) { $0 + Double($1) * Double($1) }
                let rms = sqrt(sumOfSquares / Double(chunkSamples.count))
                let normalized = Float(rms / Double(Int16.max))
                samples.append(normalized)
            }

            if samples.isEmpty {
                // No audio data, return flat waveform
                samples = Array(repeating: 0.0, count: targetSampleCount)
            }

            let sampleRate = Double(samples.count) / duration

            return CachedWaveform(
                samples: samples,
                duration: duration,
                sampleRate: sampleRate
            )
        } catch {
            throw CacheError.waveformGenerationFailed(error.localizedDescription)
        }
    }

    /// Create cache directories
    private func createCacheDirectories() {
        guard projectDirectory != nil else {
            return
        }

        // Create thumbnail cache directory
        if let thumbnailDir = cacheDirectory,
           !FileManager.default.fileExists(atPath: thumbnailDir) {
            try? FileManager.default.createDirectory(
                atPath: thumbnailDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Create waveform cache directory
        if configuration.enableWaveformCache,
           let waveformDir = waveformCacheDirectory,
           !FileManager.default.fileExists(atPath: waveformDir) {
            try? FileManager.default.createDirectory(
                atPath: waveformDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    /// Save thumbnail to disk cache
    private func saveThumbnailToDisk(_ thumbnail: CachedThumbnail, at time: TimeInterval) throws {
        guard let cacheDir = cacheDirectory else {
            throw CacheError.cacheDirectoryNotAccessible
        }

        let fileName = String(format: "thumbnail_%.3f.png", time)
        let filePath = (cacheDir as NSString).appendingPathComponent(fileName)

        try thumbnail.imageData.write(to: URL(fileURLWithPath: filePath))
    }

    /// Load thumbnail from disk cache
    private func loadThumbnailFromDisk(at time: TimeInterval) throws -> CachedThumbnail {
        guard let cacheDir = cacheDirectory else {
            throw CacheError.cacheDirectoryNotAccessible
        }

        let fileName = String(format: "thumbnail_%.3f.png", time)
        let filePath = (cacheDir as NSString).appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw CacheError.thumbnailGenerationFailed("Thumbnail not found in cache")
        }

        let imageData = try Data(contentsOf: URL(fileURLWithPath: filePath))

        // We can't easily get image dimensions from PNG data without decoding,
        // so we'll use the configured dimensions
        return CachedThumbnail(
            time: time,
            imageData: imageData,
            width: configuration.thumbnailWidth,
            height: configuration.thumbnailHeight
        )
    }

    /// Save waveform to disk cache
    private func saveWaveformToDisk(_ waveform: CachedWaveform, for trackPath: String) throws {
        guard let cacheDir = waveformCacheDirectory else {
            throw CacheError.cacheDirectoryNotAccessible
        }

        let fileName = ((trackPath as NSString).lastPathComponent as NSString).deletingPathExtension + "_waveform.json"
        let filePath = (cacheDir as NSString).appendingPathComponent(fileName)

        // Create JSON representation
        let json: [String: Any] = [
            "samples": waveform.samples,
            "duration": waveform.duration,
            "sampleRate": waveform.sampleRate
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes])
        try jsonData.write(to: URL(fileURLWithPath: filePath))
    }

    /// Load waveform from disk cache
    private func loadWaveformFromDisk(for trackPath: String) throws -> CachedWaveform {
        guard let cacheDir = waveformCacheDirectory else {
            throw CacheError.cacheDirectoryNotAccessible
        }

        let fileName = ((trackPath as NSString).lastPathComponent as NSString).deletingPathExtension + "_waveform.json"
        let filePath = (cacheDir as NSString).appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw CacheError.waveformGenerationFailed("Waveform not found in cache")
        }

        let jsonData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        guard let samples = json?["samples"] as? [Float],
              let duration = json?["duration"] as? TimeInterval,
              let sampleRate = json?["sampleRate"] as? Double else {
            throw CacheError.waveformGenerationFailed("Invalid waveform cache data")
        }

        return CachedWaveform(
            samples: samples,
            duration: duration,
            sampleRate: sampleRate
        )
    }
}

// MARK: - CGImage Extension

extension CGImage {
    /// Convert CGImage to PNG data
    fileprivate func pngData() throws -> Data {
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
