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
    static func speechOnTimeline(_ spoken: [ClosedRange<TimeInterval>], clips: [Project.TimelineClip]) -> [ClosedRange<TimeInterval>] {
        var mapped: [ClosedRange<TimeInterval>] = []
        for clip in clips {
            guard let ref = clip.recordingRef, ref.audioMuted != true else { continue }
            let toTimeline = { (source: TimeInterval) in clip.timelineIn + (source - ref.sourceIn) / clip.speed }
            for span in spoken {
                let start = max(span.lowerBound, ref.sourceIn), end = min(span.upperBound, ref.sourceOut)
                if start < end { mapped.append(toTimeline(start)...toTimeline(end)) }
            }
        }
        return mapped
    }

    static func envelope(speech: [ClosedRange<TimeInterval>], over span: Range<TimeInterval>, level: Double) -> Envelope {
        let low = Float(level)
        var envelope = Envelope(initial: 1, ramps: [])

        func ramp(from start: TimeInterval, to end: TimeInterval, reaching value: Float) {
            let current = envelope.ramps.last?.to ?? envelope.initial
            // A ramp cut by the clip's edges starts or ends partway.
            let level = { (time: TimeInterval) in current + (value - current) * Float((time - start) / (end - start)) }
            let from = max(start, span.lowerBound), to = min(end, span.upperBound)
            guard from < to else {
                if end <= span.lowerBound { envelope.initial = value }
                return
            }
            if start < from { envelope.initial = level(from) }
            envelope.ramps.append(.init(start: from, end: to, from: level(from), to: to < end ? level(to) : value))
        }

        for phrase in merged(speech) {
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
    public static func envelopes(for project: Project, directory: URL) -> [String: Envelope] {
        envelopes(for: project, transcript: try? TranscriptionEngine.Transcript.load(fromProject: directory))
    }

    static func envelopes(for project: Project, transcript load: @autoclosure () -> TranscriptionEngine.Transcript?) -> [String: Envelope] {
        let ducked = project.timeline.audioTracks.compactMap { track in track.duckingLevel.map { (track, $0) } }
        guard !ducked.isEmpty, let transcript = load() else { return [:] }

        let spoken = transcript.segments.filter { $0.start < $0.end }.map { $0.start...$0.end }
        // The transcript covers the first take only.
        let firstTake = (project.timeline.primaryTrack?.clips ?? []).filter { clip in
            clip.recordingRef.map { $0.takeId == nil || $0.takeId == project.takes.first?.id } ?? false
        }
        let speech = speechOnTimeline(spoken, clips: firstTake)
        var envelopes: [String: Envelope] = [:]
        for (track, level) in ducked {
            for clip in track.clips {
                envelopes[clip.id] = envelope(speech: speech, over: clip.timelineIn..<clip.timelineOut, level: level)
            }
        }
        return envelopes
    }
}
