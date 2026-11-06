//
//  AudioDucking.swift
//  EngineKit
//
//  Lowers a track's clips while someone speaks. Worked out from the transcript each time a composition
//  is built, so it follows cuts and moves with nothing stored on the clips.
//

import Foundation

public enum AudioDucking {
    /// How a clip's level moves over the timeline, as multipliers of its volume.
    public struct Envelope: Equatable, Sendable {
        public struct Ramp: Equatable, Sendable {
            public let start: TimeInterval
            public let end: TimeInterval
            public let from: Float
            public let to: Float
        }

        public var initial: Float
        public var ramps: [Ramp]
    }

    /// The fall starts ahead of the first word, because the render knows what comes next.
    private static let attack: TimeInterval = 0.3
    private static let release: TimeInterval = 0.7
    /// Pauses shorter than this stay low. Above `attack + release`, so ramps never overlap.
    private static let bridgedPause: TimeInterval = 1.2

    /// Spoken spans in source time, mapped through the recording clips onto the timeline.
    public static func speechOnTimeline(_ spoken: [ClosedRange<TimeInterval>], clips: [Project.TimelineClip]) -> [ClosedRange<TimeInterval>] {
        var mapped: [ClosedRange<TimeInterval>] = []
        for clip in clips {
            guard case .recording(let ref) = clip.content else { continue }
            let toTimeline = { (source: TimeInterval) in clip.timelineIn + (source - ref.sourceIn) / clip.speed }
            for span in spoken {
                let start = max(span.lowerBound, ref.sourceIn), end = min(span.upperBound, ref.sourceOut)
                if start < end { mapped.append(toTimeline(start)...toTimeline(end)) }
            }
        }
        return mapped
    }

    public static func envelope(speech: [ClosedRange<TimeInterval>], over span: Range<TimeInterval>, level: Double) -> Envelope {
        let low = Float(level)
        var envelope = Envelope(initial: 1, ramps: [])
        var current: Float = 1

        func ramp(from start: TimeInterval, to end: TimeInterval, reaching value: Float) {
            let from = max(start, span.lowerBound), to = min(end, span.upperBound)
            guard from < to else {
                if end <= span.lowerBound { envelope.initial = value; current = value }
                return
            }
            // A ramp cut short by the clip's edges ends partway.
            let reached = to < end ? current + (value - current) * Float((to - start) / (end - start)) : value
            envelope.ramps.append(.init(start: from, end: to, from: current, to: reached))
            current = reached
        }

        for phrase in merged(speech) where phrase.upperBound + release > span.lowerBound && phrase.lowerBound - attack < span.upperBound {
            ramp(from: phrase.lowerBound - attack, to: phrase.lowerBound, reaching: low)
            ramp(from: phrase.upperBound, to: phrase.upperBound + release, reaching: 1)
        }
        return envelope
    }

    private static func merged(_ speech: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
        var phrases: [ClosedRange<TimeInterval>] = []
        for span in speech.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = phrases.last, span.lowerBound - last.upperBound < bridgedPause {
                phrases[phrases.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
            } else {
                phrases.append(span)
            }
        }
        return phrases
    }

    /// One envelope per clip on a ducked track. Empty without a transcript.
    static func envelopes(for project: Project, directory: URL) -> [String: Envelope] {
        let ducked = project.timeline.audioTracks.filter { $0.duckingLevel != nil }
        guard !ducked.isEmpty,
              let data = try? Data(contentsOf: directory.appendingPathComponent("transcript/transcript.json")),
              let transcript = try? JSONDecoder().decode(TranscriptionEngine.Transcript.self, from: data) else { return [:] }

        let spoken = transcript.segments.filter { $0.start < $0.end }.map { $0.start...$0.end }
        // The transcript covers the first take only.
        let firstTake = (project.timeline.primaryTrack?.clips ?? []).filter { clip in
            guard case .recording(let ref) = clip.content else { return false }
            return ref.takeId == nil || ref.takeId == project.takes.first?.id
        }
        let speech = speechOnTimeline(spoken, clips: firstTake)
        var envelopes: [String: Envelope] = [:]
        for track in ducked {
            for clip in track.clips {
                envelopes[clip.id] = envelope(speech: speech, over: clip.timelineIn..<clip.timelineOut, level: track.duckingLevel ?? 1)
            }
        }
        return envelopes
    }
}
