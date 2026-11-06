//
//  MusicRenderer.swift
//  EngineKit
//
//  Renders a score to an audio file through Web Audio's offline context, so the length is exact and
//  the same score and seed give the same sound. See docs/FEATURES/MUSIC.md.
//

import AVFoundation
import WebKit

/// The built-in scores, implemented in ScoreKit+Styles.
public enum MusicStyle: String, CaseIterable, Codable, Sendable {
    case ambient, lofi, corporate, tech, cinematic, acoustic
}

public enum MusicScore: Equatable, Codable, Sendable {
    case style(MusicStyle)
    /// The body of a `function (m, options)`; `m` is the ScoreKit.
    case code(String)
}

public struct MusicRenderOptions: Equatable, Codable, Sendable {
    public var duration: TimeInterval
    public var seed: Int
    public var bpm: Double?
    public var key: String?
    /// How much plays at once, 0-1.
    public var intensity: Double

    public init(duration: TimeInterval, seed: Int = 1, bpm: Double? = nil, key: String? = nil, intensity: Double = 0.5) {
        self.duration = duration
        self.seed = seed
        self.bpm = bpm
        self.key = key
        self.intensity = intensity
    }
}

public enum MusicError: LocalizedError {
    case invalidOptions(String)
    case scoreFailed(String)
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOptions(let reason): return "Invalid music options: \(reason)"
        case .scoreFailed(let reason): return "The score failed: \(reason)"
        case .writerFailed(let reason): return "Could not write the audio: \(reason)"
        }
    }
}

@MainActor
public enum MusicRenderer {
    nonisolated public static let maxDuration: TimeInterval = 600
    nonisolated private static let maxCodeBytes = 256 * 1024
    private static let sampleRate = 48_000
    private static let framesPerChunk = sampleRate * 5
    private static let renderTimeout: TimeInterval = 240

    nonisolated public static func validate(_ source: MusicSource) throws {
        let options = source.options
        guard (1...maxDuration).contains(options.duration) else {
            throw MusicError.invalidOptions("duration must be 1-\(Int(maxDuration)) seconds; use a second clip for longer videos")
        }
        guard (0...1).contains(options.intensity) else { throw MusicError.invalidOptions("intensity must be 0-1") }
        if let bpm = options.bpm, !(40...200).contains(bpm) { throw MusicError.invalidOptions("bpm must be 40-200") }
        if case .code(let code) = source.score, code.utf8.count > maxCodeBytes {
            throw MusicError.invalidOptions("code is larger than \(maxCodeBytes / 1024) KB")
        }
    }

    /// Renders to an AAC .m4a at `url`. Returns the seconds written.
    @discardableResult
    public static func render(_ source: MusicSource, to url: URL) async throws -> TimeInterval {
        try validate(source)
        // MCP renders run with the app in the back.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Rendering music")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        let page = HeadlessPage(size: CGSize(width: 16, height: 16), stepTimeout: 30, failure: { MusicError.scoreFailed($0) })
        defer { page.close() }
        try await page.load("<!doctype html><script>\(ScoreKit.script)</script>")

        let options = source.options
        var settings: [String: Any] = ["duration": options.duration, "seed": options.seed, "intensity": options.intensity]
        settings["bpm"] = options.bpm
        settings["key"] = options.key
        var request: [String: Any] = ["options": settings, "sampleRate": sampleRate]
        switch source.score {
        case .style(let style): request["style"] = style.rawValue
        case .code(let code): request["code"] = code
        }
        let frames = Int(try await page.run("return await Score.render(request);", arguments: ["request": request],
                                            step: "rendering the score", timeout: renderTimeout))

        let sink = try AudioSink(url: url, sampleRate: Double(sampleRate))
        do {
            for start in stride(from: 0, to: frames, by: framesPerChunk) {
                let count = min(framesPerChunk, frames - start)
                let encoded = try await page.text("return Score.chunk(start, count);", arguments: ["start": start, "count": count],
                                                  step: "reading the audio")
                try await sink.append(encoded, frames: count)
            }
            await sink.close()
        } catch {
            await sink.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return Double(frames) / Double(sampleRate)
    }
}

/// Encodes audio off the main actor so the editor stays responsive.
private actor AudioSink {
    private var file: AVAudioFile?
    private let format: AVAudioFormat

    init(url: URL, sampleRate: Double) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw MusicError.writerFailed("no stereo format")
        }
        self.format = format
        do {
            file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw MusicError.writerFailed(error.localizedDescription)
        }
    }

    /// `encoded` is base64 of Float32 samples: all of the left channel, then the right.
    func append(_ encoded: String, frames: Int) throws {
        guard let data = Data(base64Encoded: encoded), data.count == frames * 2 * MemoryLayout<Float32>.size,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            throw MusicError.writerFailed("the page returned bad audio")
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Float32.self)
            channels[0].update(from: samples.baseAddress!, count: frames)
            channels[1].update(from: samples.baseAddress! + frames, count: frames)
        }
        do {
            try file?.write(from: buffer)
        } catch {
            throw MusicError.writerFailed(error.localizedDescription)
        }
    }

    /// AVAudioFile finishes the file when released.
    func close() { file = nil }
}
