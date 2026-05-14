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
    // MARK: - Properties

    private var project: Project?
    private var projectDirectory: String?
    private let configuration: Configuration
    /// Keyed by quantized milliseconds (see `bucket(for:)`) so float equality
    /// drift on TimeInterval can't cause ghost misses.
    private var thumbnailCache: [Int: CachedThumbnail] = [:]
    private var thumbnailAccessOrder: [Int] = []
    private var waveformCache: [String: CachedWaveform] = [:]

    /// Round to milliseconds to avoid float-equality misses on TimeInterval keys.
    private static func bucket(for time: TimeInterval) -> Int {
        Int((time * 1000).rounded())
    }

    private var cacheDirectory: String? {
        guard let projectDir = projectDirectory else { return nil }
        return (projectDir as NSString).appendingPathComponent("cache/thumbnails")
    }

    private var waveformCacheDirectory: String? {
        guard let projectDir = projectDirectory else { return nil }
        return (projectDir as NSString).appendingPathComponent("cache/waveforms")
    }

    // MARK: - Initialization

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func setProject(_ project: Project, projectDirectory: String) {
        self.project = project
        self.projectDirectory = projectDirectory
        thumbnailCache.removeAll()
        thumbnailAccessOrder.removeAll()
        waveformCache.removeAll()
        if configuration.enableDiskCache {
            createCacheDirectories()
        }
    }

    public func clearProject() {
        self.project = nil
        self.projectDirectory = nil
        thumbnailCache.removeAll()
        thumbnailAccessOrder.removeAll()
        waveformCache.removeAll()
    }

    // MARK: - LRU Helpers

    private func insertThumbnail(_ thumbnail: CachedThumbnail, at time: TimeInterval) {
        let key = Self.bucket(for: time)
        thumbnailCache[key] = thumbnail
        thumbnailAccessOrder.removeAll { $0 == key }
        thumbnailAccessOrder.append(key)
        evictThumbnailsIfNeeded()
    }

    private func evictThumbnailsIfNeeded() {
        while thumbnailCache.count > configuration.maxThumbnailCount,
              let oldest = thumbnailAccessOrder.first {
            thumbnailAccessOrder.removeFirst()
            thumbnailCache.removeValue(forKey: oldest)
        }
    }

    // MARK: - Thumbnail Operations

    public func getThumbnails(
        count: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> [CachedThumbnail] {
        guard let project = project else { throw CacheError.projectNotSet }

        let duration = endTime - startTime
        let interval = duration / Double(max(count - 1, 1))
        var thumbnails: [CachedThumbnail] = []

        for i in 0..<count {
            let time = startTime + (Double(i) * interval)

            if let cached = thumbnailCache[Self.bucket(for: time)] {
                thumbnails.append(cached)
                continue
            }

            if configuration.enableDiskCache,
               let diskCached = try? loadThumbnailFromDisk(at: time) {
                thumbnails.append(diskCached)
                insertThumbnail(diskCached, at: time)
                continue
            }

            let thumbnail = try await generateThumbnail(at: time, for: project)
            thumbnails.append(thumbnail)
            insertThumbnail(thumbnail, at: time)

            if configuration.enableDiskCache {
                try? saveThumbnailToDisk(thumbnail, at: time)
            }
        }

        return thumbnails
    }

    public func getThumbnail(at time: TimeInterval) async throws -> CachedThumbnail {
        guard let project = project else { throw CacheError.projectNotSet }

        let key = Self.bucket(for: time)
        if let cached = thumbnailCache[key] { return cached }

        if configuration.enableDiskCache,
           let diskCached = try? loadThumbnailFromDisk(at: time) {
            thumbnailCache[key] = diskCached
            return diskCached
        }

        let thumbnail = try await generateThumbnail(at: time, for: project)
        insertThumbnail(thumbnail, at: time)
        if configuration.enableDiskCache {
            try? saveThumbnailToDisk(thumbnail, at: time)
        }
        return thumbnail
    }

    public func generateAllThumbnails(progress: ((Double) -> Void)? = nil) async throws -> Int {
        guard let project = project else { throw CacheError.projectNotSet }

        let duration = project.timeline.duration
        let thumbnailCount = min(configuration.maxThumbnailCount, Int(duration) + 1)
        let interval = duration / Double(max(thumbnailCount - 1, 1))
        var generatedCount = 0

        for i in 0..<thumbnailCount {
            let time = Double(i) * interval

            if thumbnailCache[Self.bucket(for: time)] != nil { generatedCount += 1; continue }
            if configuration.enableDiskCache, (try? loadThumbnailFromDisk(at: time)) != nil {
                generatedCount += 1; continue
            }

            let thumbnail = try await generateThumbnail(at: time, for: project)
            insertThumbnail(thumbnail, at: time)
            if configuration.enableDiskCache { try? saveThumbnailToDisk(thumbnail, at: time) }
            generatedCount += 1
            progress?(Double(i + 1) / Double(thumbnailCount))
        }

        return generatedCount
    }

    public func clearThumbnails() {
        thumbnailCache.removeAll()
        thumbnailAccessOrder.removeAll()
        if configuration.enableDiskCache, let cacheDir = cacheDirectory {
            try? FileManager.default.removeItem(atPath: cacheDir)
            createCacheDirectories()
        }
    }

    // MARK: - Waveform Operations

    public func getWaveform(for trackPath: String) async throws -> CachedWaveform {
        guard configuration.enableWaveformCache else {
            throw CacheError.waveformGenerationFailed("Waveform caching is disabled")
        }

        if let cached = waveformCache[trackPath] { return cached }

        if configuration.enableDiskCache,
           let diskCached = try? loadWaveformFromDisk(for: trackPath) {
            waveformCache[trackPath] = diskCached
            return diskCached
        }

        let waveform = try await generateWaveform(for: trackPath)
        waveformCache[trackPath] = waveform
        if configuration.enableDiskCache { try? saveWaveformToDisk(waveform, for: trackPath) }
        return waveform
    }

    public func generateAllWaveforms(progress: ((Double) -> Void)? = nil) async throws -> Int {
        guard let project = project else { throw CacheError.projectNotSet }
        guard configuration.enableWaveformCache else { return 0 }
        guard let sources = project.primarySources else { return 0 }

        var trackPaths: [String] = []
        if let audio = sources.audio, let systemAudio = audio.system { trackPaths.append(systemAudio.path) }
        if let audio = sources.audio, let micAudio = audio.mic { trackPaths.append(micAudio.path) }

        var generatedCount = 0
        for (index, trackPath) in trackPaths.enumerated() {
            if waveformCache[trackPath] != nil { generatedCount += 1; continue }
            if configuration.enableDiskCache, (try? loadWaveformFromDisk(for: trackPath)) != nil {
                generatedCount += 1; continue
            }

            let waveform = try await generateWaveform(for: trackPath)
            waveformCache[trackPath] = waveform
            if configuration.enableDiskCache { try? saveWaveformToDisk(waveform, for: trackPath) }
            generatedCount += 1
            progress?(Double(index + 1) / Double(trackPaths.count))
        }

        return generatedCount
    }

    public func clearWaveforms() {
        waveformCache.removeAll()
        if configuration.enableDiskCache, let cacheDir = waveformCacheDirectory {
            try? FileManager.default.removeItem(atPath: cacheDir)
            createCacheDirectories()
        }
    }

    public func clearAll() {
        clearThumbnails()
        clearWaveforms()
    }

    // MARK: - Cache Statistics

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
        stats["thumbnailMemoryBytes"] = thumbnailCache.values.reduce(0) { $0 + $1.imageData.count }
        stats["waveformMemoryBytes"] = waveformCache.values.reduce(0) { $0 + $1.samples.count * MemoryLayout<Float>.size }
        return stats
    }

    // MARK: - Private Generators

    private func generateThumbnail(at time: TimeInterval, for project: Project) async throws -> CachedThumbnail {
        guard let sources = project.primarySources else {
            throw CacheError.mediaFileNotFound("No sources found")
        }
        let screenPath = sources.screen.path

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
            let imageData = try cgImage.pngData()
            return CachedThumbnail(time: time, imageData: imageData, width: cgImage.width, height: cgImage.height)
        } catch {
            throw CacheError.thumbnailGenerationFailed(error.localizedDescription)
        }
    }

    private func generateWaveform(for trackPath: String) async throws -> CachedWaveform {
        guard FileManager.default.fileExists(atPath: trackPath) else {
            throw CacheError.mediaFileNotFound(trackPath)
        }

        let asset = AVAsset(url: URL(fileURLWithPath: trackPath))

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let audioTrack = audioTracks.first else {
                throw CacheError.waveformGenerationFailed("No audio track found")
            }

            let duration = try await asset.load(.duration).seconds
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

            var samples: [Float] = []
            let targetSampleCount = configuration.waveformResolution
            let samplesPerChunk = max(1, Int(duration * 44100) / targetSampleCount)
            var chunkSamples: [Int16] = []

            while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let result = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

                guard result == noErr, let pointer = dataPointer else { continue }

                let int16Pointer = pointer.withMemoryRebound(to: Int16.self, capacity: totalLength / 2) { $0 }

                for i in 0..<(totalLength / MemoryLayout<Int16>.size) {
                    chunkSamples.append(int16Pointer[i])

                    if chunkSamples.count >= samplesPerChunk {
                        let sumOfSquares = chunkSamples.reduce(0.0) { $0 + Double($1) * Double($1) }
                        let rms = sqrt(sumOfSquares / Double(chunkSamples.count))
                        samples.append(Float(rms / Double(Int16.max)))
                        chunkSamples.removeAll()
                        if samples.count >= targetSampleCount { break }
                    }
                }
                if samples.count >= targetSampleCount { break }
            }

            if !chunkSamples.isEmpty && samples.count < targetSampleCount {
                let sumOfSquares = chunkSamples.reduce(0.0) { $0 + Double($1) * Double($1) }
                let rms = sqrt(sumOfSquares / Double(chunkSamples.count))
                samples.append(Float(rms / Double(Int16.max)))
            }

            if samples.isEmpty { samples = Array(repeating: 0.0, count: targetSampleCount) }

            return CachedWaveform(samples: samples, duration: duration, sampleRate: Double(samples.count) / duration)
        } catch {
            throw CacheError.waveformGenerationFailed(error.localizedDescription)
        }
    }

    // MARK: - Disk I/O

    private func createCacheDirectories() {
        guard projectDirectory != nil else { return }
        if let thumbnailDir = cacheDirectory, !FileManager.default.fileExists(atPath: thumbnailDir) {
            try? FileManager.default.createDirectory(atPath: thumbnailDir, withIntermediateDirectories: true, attributes: nil)
        }
        if configuration.enableWaveformCache, let waveformDir = waveformCacheDirectory, !FileManager.default.fileExists(atPath: waveformDir) {
            try? FileManager.default.createDirectory(atPath: waveformDir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func saveThumbnailToDisk(_ thumbnail: CachedThumbnail, at time: TimeInterval) throws {
        guard let cacheDir = cacheDirectory else { throw CacheError.cacheDirectoryNotAccessible }
        let filePath = (cacheDir as NSString).appendingPathComponent(String(format: "thumbnail_%.3f.png", time))
        try thumbnail.imageData.write(to: URL(fileURLWithPath: filePath))
    }

    private func loadThumbnailFromDisk(at time: TimeInterval) throws -> CachedThumbnail {
        guard let cacheDir = cacheDirectory else { throw CacheError.cacheDirectoryNotAccessible }
        let filePath = (cacheDir as NSString).appendingPathComponent(String(format: "thumbnail_%.3f.png", time))
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw CacheError.thumbnailGenerationFailed("Thumbnail not found in cache")
        }
        let imageData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return CachedThumbnail(time: time, imageData: imageData, width: configuration.thumbnailWidth, height: configuration.thumbnailHeight)
    }

    private func saveWaveformToDisk(_ waveform: CachedWaveform, for trackPath: String) throws {
        guard let cacheDir = waveformCacheDirectory else { throw CacheError.cacheDirectoryNotAccessible }
        let fileName = ((trackPath as NSString).lastPathComponent as NSString).deletingPathExtension + "_waveform.json"
        let filePath = (cacheDir as NSString).appendingPathComponent(fileName)
        let json: [String: Any] = ["samples": waveform.samples, "duration": waveform.duration, "sampleRate": waveform.sampleRate]
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes])
        try jsonData.write(to: URL(fileURLWithPath: filePath))
    }

    private func loadWaveformFromDisk(for trackPath: String) throws -> CachedWaveform {
        guard let cacheDir = waveformCacheDirectory else { throw CacheError.cacheDirectoryNotAccessible }
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
        return CachedWaveform(samples: samples, duration: duration, sampleRate: sampleRate)
    }
}
