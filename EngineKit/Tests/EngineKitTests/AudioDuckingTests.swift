import AVFoundation
import XCTest
@testable import EngineKit

final class AudioDuckingTests: XCTestCase {
    private func recording(at start: TimeInterval, source: ClosedRange<TimeInterval>, speed: Double = 1) -> Project.TimelineClip {
        Project.TimelineClip(timelineIn: start, content: .recording(Project.RecordingClipRef(sourceIn: source.lowerBound, sourceOut: source.upperBound)), speed: speed)
    }

    func testSpeechFollowsCutsAndSpeed() {
        let clips = [recording(at: 0, source: 10...20), recording(at: 10, source: 40...50, speed: 2)]
        let speech = AudioDucking.speechOnTimeline([12...14, 18...45], clips: clips)
        XCTAssertEqual(speech, [2...4, 8...10, 10...12.5])
    }

    func testFallsBeforeSpeechAndRisesAfter() {
        let envelope = AudioDucking.envelope(speech: [10...12], over: 0..<30, level: 0.5)
        XCTAssertEqual(envelope.initial, 1)
        XCTAssertEqual(envelope.ramps, [
            .init(start: 9.7, end: 10, from: 1, to: 0.5),
            .init(start: 12, end: 12.7, from: 0.5, to: 1),
        ])
    }

    func testShortPausesStayLow() {
        let envelope = AudioDucking.envelope(speech: [10...12, 12.8...14, 20...21], over: 0..<30, level: 0.5)
        XCTAssertEqual(envelope.ramps.count, 4, "the first two spans are one phrase")
        XCTAssertEqual(envelope.ramps[1].start, 14)
    }

    func testAClipStartingInSpeechStartsLow() {
        let envelope = AudioDucking.envelope(speech: [0...5], over: 3..<30, level: 0.4)
        XCTAssertEqual(envelope.initial, 0.4)
        XCTAssertEqual(envelope.ramps, [.init(start: 5, end: 5.7, from: 0.4, to: 1)])
    }

    func testRampsStayInsideTheClip() {
        let envelope = AudioDucking.envelope(speech: [9.9...12, 40...50], over: 5..<10, level: 0.5)
        XCTAssertEqual(envelope.ramps.count, 1)
        XCTAssertEqual(envelope.ramps[0].end, 9.9, accuracy: 0.001, "the fall ends with the clip's speech")
    }

    func testARampCutByTheClipEndsPartway() {
        let envelope = AudioDucking.envelope(speech: [10...12], over: 0..<9.85, level: 0)
        XCTAssertEqual(envelope.ramps.count, 1)
        XCTAssertEqual(envelope.ramps[0].end, 9.85)
        XCTAssertEqual(envelope.ramps[0].to, 0.5, accuracy: 0.001)
    }

    func testRampsNeverOverlap() {
        let speech = stride(from: 0.0, to: 100, by: 2.1).map { $0...($0 + 0.5) } + [120...121, 122.3...123]
        let ramps = AudioDucking.envelope(speech: speech, over: 0..<200, level: 0.3).ramps
        for (a, b) in zip(ramps, ramps.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start) }
    }

    func testEnvelopesNeedATranscriptAndADuckedTrack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("transcript"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let text = #"{"language":"es","duration":30,"segments":[{"id":0,"start":2,"end":4,"text":"hola"}]}"#
        let music = Project.TimelineClip(timelineIn: 0, content: .audio(Project.AudioClipRef(path: "assets/m.m4a", duration: 30)))
        let tracks = [
            Project.TimelineTrack(id: Project.TimelineTrack.primaryTrackId, type: .primary, clips: [recording(at: 0, source: 0...30)]),
            Project.TimelineTrack(name: "Music", type: .audio, clips: [music]),
        ]
        var project = Project(
            projectId: UUID(), name: "ducking", timeline: Project.Timeline(duration: 30, tracks: tracks),
            canvas: Project.Canvas(format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                                   background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                                   layout: Project.Canvas.Layout(type: "pip", camera: nil)))
        let index = 1

        project.timeline.tracks[index].duckingLevel = 0.5
        XCTAssertTrue(AudioDucking.envelopes(for: project, directory: directory).isEmpty, "no transcript yet")
        try text.write(to: directory.appendingPathComponent("transcript/transcript.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AudioDucking.envelopes(for: project, directory: directory)[music.id]?.ramps.count, 2)
        project.timeline.tracks[index].duckingLevel = nil
        XCTAssertTrue(AudioDucking.envelopes(for: project, directory: directory).isEmpty)
    }

    func testTheMixFollowsTheEnvelope() throws {
        let composition = AVMutableComposition()
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        let params = AVMutableAudioMixInputParameters(track: track)
        let envelope = AudioDucking.envelope(speech: [10...12], over: 0..<30, level: 0.5)
        AudioMixBuilder.apply(envelope, volume: 0.4, to: params)

        var start: Float = 0, end: Float = 0
        var range = CMTimeRange.zero
        XCTAssertTrue(params.getVolumeRamp(for: CMTime(seconds: 9.8, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(start, 0.4, accuracy: 0.001)
        XCTAssertEqual(end, 0.2, accuracy: 0.001)
    }
}
