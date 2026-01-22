//
//  AIServiceLocalProcessing.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import CoreMedia

extension AIService {
    // MARK: - Local AI Implementation

    /// Detect silent regions in audio
    func detectSilence(
        audioPath: URL,
        threshold: Float,
        minDuration: TimeInterval
    ) async throws -> [SilentRegion] {
        // Load audio asset
        let asset = AVAsset(url: audioPath)
        let duration = try await asset.load(.duration).seconds

        // Use AVAssetReader to analyze audio samples
        let reader = try AVAssetReader(asset: asset)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        guard let audioTrack = audioTrack else {
            throw AIServiceError.audioAnalysisFailed("No audio track found")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var silentRegions: [SilentRegion] = []
        var inSilence = false
        var silenceStart: TimeInterval = 0
        var currentTime: TimeInterval = 0
        let sampleRate: Double = 44100 // Default, will be read from asset
        _ = sampleRate

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let samples = sampleBuffer.dataBuffer else {
                try? sampleBuffer.invalidate()
                continue
            }

            // Calculate RMS (root mean square) of audio samples
            let rms = calculateAudioRMS(samples: samples, sampleBuffer: sampleBuffer)

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            currentTime = CMTimeGetSeconds(presentationTime)

            if rms < threshold {
                // Silence detected
                if !inSilence {
                    inSilence = true
                    silenceStart = currentTime
                }
            } else {
                // Sound detected
                if inSilence {
                    let silenceDuration = currentTime - silenceStart
                    if silenceDuration >= minDuration {
                        silentRegions.append(SilentRegion(
                            startTime: silenceStart,
                            endTime: currentTime,
                            duration: silenceDuration
                        ))
                    }
                    inSilence = false
                }
            }

            try? sampleBuffer.invalidate()
        }

        // Handle silence at end of audio
        if inSilence {
            let silenceDuration = duration - silenceStart
            if silenceDuration >= minDuration {
                silentRegions.append(SilentRegion(
                    startTime: silenceStart,
                    endTime: duration,
                    duration: silenceDuration
                ))
            }
        }

        reader.cancelReading()

        return silentRegions
    }

    /// Calculate RMS of audio samples
    private func calculateAudioRMS(samples: CMBlockBuffer, sampleBuffer: CMSampleBuffer) -> Float {
        var rms: Float = 0.0

        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            samples,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: nil,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let pointer = dataPointer else {
            return rms
        }

        let dataLength = CMBlockBufferGetDataLength(samples)
        let sampleCount = dataLength / MemoryLayout<Int16>.size
        let int16Pointer = pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }

        var sum: Float = 0
        for i in 0..<sampleCount {
            let sample = Float(abs(Int16(int16Pointer[i])))
            sum += sample * sample
        }

        rms = sqrt(sum / Float(sampleCount))
        return rms / Float(Int16.max)
    }

    /// Suggest chapters from transcript
    func suggestChaptersFromTranscript(
        transcript: Transcript,
        minChapterDuration: TimeInterval,
        maxChapters: Int
    ) async throws -> [ChapterSuggestion] {
        var chapters: [ChapterSuggestion] = []
        var currentChapterSegments: [Transcript.Segment] = []
        var chapterStartTime: TimeInterval = 0

        for segment in transcript.segments {
            currentChapterSegments.append(segment)

            let chapterDuration = segment.endTime - chapterStartTime

            // Check if we should end the chapter
            if chapterDuration >= minChapterDuration || isChapterBoundary(segment: segment) {
                // Create chapter from segments
                let chapter = createChapterFromSegments(
                    segments: currentChapterSegments,
                    startTime: chapterStartTime,
                    endTime: segment.endTime
                )
                chapters.append(chapter)

                // Start new chapter
                currentChapterSegments = []
                chapterStartTime = segment.endTime

                // Check if we've reached max chapters
                if chapters.count >= maxChapters {
                    break
                }
            }
        }

        // Handle remaining segments
        if !currentChapterSegments.isEmpty {
            let lastSegment = currentChapterSegments.last!
            let chapter = createChapterFromSegments(
                segments: currentChapterSegments,
                startTime: chapterStartTime,
                endTime: lastSegment.endTime
            )
            chapters.append(chapter)
        }

        return chapters
    }

    /// Check if a segment is a chapter boundary
    private func isChapterBoundary(segment: Transcript.Segment) -> Bool {
        // Simple heuristic: pause > 2 seconds or question mark/exclamation
        let gap = segment.startTime - (segment.endTime)
        let text = segment.text.lowercased()

        return gap > 2.0 ||
               text.hasSuffix("?") ||
               text.hasSuffix("!") ||
               text.contains("chapter") ||
               text.contains("section") ||
               text.contains("next")
    }

    /// Create chapter from transcript segments
    private func createChapterFromSegments(
        segments: [Transcript.Segment],
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> ChapterSuggestion {
        // Combine text from all segments
        let text = segments.map { $0.text }.joined(separator: " ")

        // Extract keywords (simple: most frequent words)
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let wordCounts = Dictionary(grouping: words, by: { $0 }).mapValues { $0.count }
        let sortedWords = wordCounts.sorted { $0.value > $1.value }
        let keywords = Array(sortedWords.prefix(5).map { $0.key })

        // Generate title from first few words
        let titleWords = words.prefix(5)
        let title = titleWords.joined(separator: " ").capitalized

        // Generate summary from first and last sentences
        let summary = "\(text.prefix(100))..."

        return ChapterSuggestion(
            title: title,
            startTime: startTime,
            endTime: endTime,
            confidence: 0.7,
            summary: summary,
            keywords: keywords
        )
    }
}
