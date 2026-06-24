//
//  WhisperKitTranscriber.swift
//  EngineKit
//
//  On-device speech-to-text via WhisperKit (CoreML / Apple Neural Engine).
//  Gated to Apple Silicon: on Intel Macs `isSupported` is false and callers
//  surface a "not available yet" message instead of running.
//

import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

/// Lightweight hardware capability checks.
enum SystemCapabilities {
    /// True on Apple Silicon (M-series), including under Rosetta. Uses the
    /// `hw.optional.arm64` sysctl, which reports the real CPU rather than the
    /// process architecture.
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }()
}

/// Bridges WhisperKit into the transcription pipeline. Kept isolated so the rest
/// of EngineKit doesn't depend on WhisperKit symbols directly.
enum WhisperKitTranscriber {
    /// A timed transcript segment (seconds).
    struct Segment {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    /// Whether on-device transcription can run on this machine.
    static var isSupported: Bool {
        #if canImport(WhisperKit)
        return SystemCapabilities.isAppleSilicon
        #else
        return false
        #endif
    }

    /// Transcribe a (16 kHz mono) audio file into timed segments.
    /// - Parameters:
    ///   - audioPath: Path to the audio file (WAV produced by the engine).
    ///   - modelName: WhisperKit model identifier (e.g. "base", "small").
    ///   - language: BCP-47 / ISO code, or nil to auto-detect.
    /// - Parameter onModelReady: called once the model is downloaded + loaded,
    ///   just before transcription begins — lets callers advance progress past
    ///   the long (and otherwise opaque) first-run download phase.
    static func transcribe(
        audioPath: URL,
        modelName: String,
        language: String?,
        translate: Bool = false,
        onModelReady: (@Sendable () async -> Void)? = nil
    ) async throws -> (language: String, segments: [Segment]) {
        guard SystemCapabilities.isAppleSilicon else {
            throw TranscriptionError.unsupportedHardware
        }

        #if canImport(WhisperKit)
        // First run downloads the CoreML model (needs network.client entitlement);
        // subsequent runs load from the on-disk cache.
        let pipe = try await WhisperKit(WhisperKitConfig(model: modelName))
        await onModelReady?()
        // detectLanguage when no language is given — otherwise WhisperKit defaults
        // to English (why Spanish came back as English). skipSpecialTokens +
        // withoutTimestamps keep the text clean (no <|…|> / <|x.xx|> tokens).
        let options = DecodingOptions(
            task: translate ? .translate : .transcribe,
            language: language,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await pipe.transcribe(audioPath: audioPath.path, decodeOptions: options)

        var segments: [Segment] = []
        var detectedLanguage = language ?? "en"
        for result in results {
            if !result.language.isEmpty { detectedLanguage = result.language }
            for segment in result.segments {
                let text = cleanText(segment.text)
                guard !text.isEmpty else { continue }
                segments.append(Segment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: text
                ))
            }
        }
        return (detectedLanguage, segments)
        #else
        throw TranscriptionError.transcriberUnavailable
        #endif
    }

    /// Strip any residual Whisper special tokens (`<|startoftranscript|>`,
    /// `<|en|>`, `<|4.00|>`, …) that slip through when a model ignores
    /// skipSpecialTokens, then collapse whitespace.
    private static func cleanText(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
