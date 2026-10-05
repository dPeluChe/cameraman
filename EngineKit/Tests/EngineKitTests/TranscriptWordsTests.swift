import XCTest
@testable import EngineKit

final class TranscriptWordsTests: XCTestCase {
    private typealias Transcript = TranscriptionEngine.Transcript

    /// Transcripts written before word timestamps existed must keep loading.
    func testTranscriptWithoutWordsStillDecodes() throws {
        let legacy = Data("""
        {"language":"en","duration":3,"segments":[{"id":0,"start":0,"end":3,"text":"hello world"}]}
        """.utf8)
        let transcript = try JSONDecoder().decode(Transcript.self, from: legacy)
        XCTAssertEqual(transcript.segments.first?.text, "hello world")
        XCTAssertNil(transcript.segments.first?.words)
    }

    func testWordsRoundTripWithTimingAndConfidence() throws {
        let words = [
            Transcript.Word(text: "hello", start: 0.1, end: 0.5, probability: 0.98),
            Transcript.Word(text: "world", start: 0.6, end: 1.0, probability: 0.31),
        ]
        let original = Transcript(language: "en", duration: 1, segments: [
            Transcript.Segment(id: 0, start: 0, end: 1, text: "hello world", words: words)
        ])
        let decoded = try JSONDecoder().decode(Transcript.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.segments.first?.words?.last?.probability ?? -1, 0.31, accuracy: 0.0001)
    }

    func testASegmentWithoutWordsOmitsTheKey() throws {
        let segment = Transcript.Segment(id: 0, start: 0, end: 1, text: "hi")
        let json = String(decoding: try JSONEncoder().encode(segment), as: UTF8.self)
        XCTAssertFalse(json.contains("words"), json)
    }
}
