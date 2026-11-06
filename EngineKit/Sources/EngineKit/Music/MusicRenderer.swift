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
public enum MusicStyle: String, CaseIterable, Sendable {
    case ambient, lofi, corporate, tech, cinematic, acoustic
}

public struct MusicRenderOptions: Sendable {
    public var duration: TimeInterval
    public var seed: Int
    public var bpm: Double?
    public var key: String?
    /// How much plays at once, 0-1.
    public var intensity: Double
    /// Longest wait for the whole score to render. Seconds.
    public var renderTimeout: TimeInterval

    public init(duration: TimeInterval, seed: Int = 1, bpm: Double? = nil, key: String? = nil,
                intensity: Double = 0.5, renderTimeout: TimeInterval = 240) {
        self.duration = duration
        self.seed = seed
        self.bpm = bpm
        self.key = key
        self.intensity = intensity
        self.renderTimeout = renderTimeout
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

public enum MusicScore: Sendable {
    case style(MusicStyle)
    /// The body of a `function (m, options)`; `m` is the ScoreKit.
    case code(String)
}

@MainActor
public enum MusicRenderer {
    public static let maxDuration: TimeInterval = 600
    private static let sampleRate = 48_000.0
    private static let framesPerChunk = 48_000 * 5

    /// Renders `score` to an AAC .m4a at `url`. Returns the seconds written.
    @discardableResult
    public static func render(score: MusicScore, to url: URL, options: MusicRenderOptions) async throws -> TimeInterval {
        guard options.duration >= 1, options.duration <= maxDuration else {
            throw MusicError.invalidOptions("duration must be 1-\(Int(maxDuration)) seconds")
        }
        // MCP renders run with the app in the back.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Rendering music")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        let page = HeadlessPage(size: CGSize(width: 16, height: 16), stepTimeout: 30, failure: { MusicError.scoreFailed($0) })
        defer { page.close() }
        try await page.load("<!doctype html><script>\(ScoreKit.script)</script>")

        var settings: [String: Any] = ["duration": options.duration, "seed": options.seed, "intensity": options.intensity]
        settings["bpm"] = options.bpm
        settings["key"] = options.key
        var request: [String: Any] = ["options": settings]
        switch score {
        case .style(let style): request["style"] = style.rawValue
        case .code(let code): request["code"] = code
        }

        let frames: Int
        do {
            frames = Int(try await page.run("return await Score.render(request);", arguments: ["request": request],
                                            step: "rendering the score", timeout: options.renderTimeout))
            try? FileManager.default.removeItem(at: url)
            try await write(frames: frames, from: page, to: url)
        } catch let error as MusicError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw MusicError.scoreFailed(pageMessage(error))
        }
        return Double(frames) / sampleRate
    }

    private static func write(frames: Int, from page: HeadlessPage, to url: URL) async throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw MusicError.writerFailed("no stereo format")
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)

            var start = 0
            while start < frames {
                let count = min(framesPerChunk, frames - start)
                let encoded = try await page.text("return Score.chunk(start, count);", arguments: ["start": start, "count": count],
                                                  step: "reading the audio")
                guard let data = Data(base64Encoded: encoded), data.count == count * 8,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let channels = buffer.floatChannelData else {
                    throw MusicError.writerFailed("the page returned bad audio")
                }
                buffer.frameLength = AVAudioFrameCount(count)
                data.withUnsafeBytes { raw in
                    let samples = raw.bindMemory(to: Float32.self)
                    channels[0].update(from: samples.baseAddress!, count: count)
                    channels[1].update(from: samples.baseAddress! + count, count: count)
                }
                try file.write(from: buffer)
                start += count
            }
        } catch let error as MusicError {
            try? FileManager.default.removeItem(at: url)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw MusicError.writerFailed(error.localizedDescription)
        }
    }

    /// WebKit keeps the script's own message apart from its generic "A JavaScript exception occurred".
    private static func pageMessage(_ error: Error) -> String {
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }
}
