import AVFoundation
import XCTest
@testable import EngineKit

@MainActor
final class MusicRendererTests: XCTestCase {
    private func tempURL() -> URL { MotionTestSupport.tempURL("music.m4a") }

    private func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func testEveryStyleRendersItsExactLengthWithSound() async throws {
        for style in MusicStyle.allCases {
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }
            let seconds = try await MusicRenderer.render(MusicSource(score: .style(style), options: MusicRenderOptions(duration: 6)), to: url)
            XCTAssertEqual(seconds, 6, accuracy: 0.001, style.rawValue)
            let track = try await AVURLAsset(url: url).load(.duration).seconds
            XCTAssertEqual(track, 6, accuracy: 0.1, style.rawValue)
            let peak = try samples(of: url).map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.1, "\(style.rawValue) must be audible")
            XCTAssertLessThan(peak, 1, "\(style.rawValue) must not clip")
        }
    }

    func testTheSameSeedGivesTheSameMusicAndAnotherDoesNot() async throws {
        let urls = (0..<3).map { _ in tempURL() }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        let seeds = [7, 7, 8]
        for (url, seed) in zip(urls, seeds) {
            try await MusicRenderer.render(MusicSource(score: .style(.acoustic), options: MusicRenderOptions(duration: 3, seed: seed)), to: url)
        }
        let (first, same, other) = (try samples(of: urls[0]), try samples(of: urls[1]), try samples(of: urls[2]))
        let difference = { (a: [Float], b: [Float]) in zip(a, b).map { abs($0 - $1) }.max() ?? 1 }
        // Renders of a seed differ by up to -54 dB from run to run: inaudible, but never assert equality.
        XCTAssertLessThan(difference(first, same), 0.005)
        XCTAssertGreaterThan(difference(first, other), 0.01)
    }

    func testVoicesOutliveTheSchedulingWindows() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let score = "m.pluck('A3', 9.5, { vel: 1 });"
        try await MusicRenderer.render(MusicSource(score: .code(score), options: MusicRenderOptions(duration: 12)), to: url)
        let audio = try samples(of: url)
        XCTAssertEqual(audio[..<(48_000 * 9)].map(abs).max() ?? 1, 0, accuracy: 0.001, "nothing before the note")
        XCTAssertGreaterThan(audio[(48_000 * 9 + 24_000)...].map(abs).max() ?? 0, 0.1, "a note in a later window must play")
    }

    func testASampleIsRenderedOnceAndKept() async throws {
        let file = try await MusicRenderer.sample(of: .tech)
        let track = try await AVURLAsset(url: file).load(.duration).seconds
        XCTAssertEqual(track, MusicRenderer.sampleDuration, accuracy: 0.1)
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        let again = try await MusicRenderer.sample(of: .tech)
        XCTAssertEqual(again, file)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date, modified)
    }

    func testScoreErrorsReachTheCaller() async {
        let url = tempURL()
        for (score, expected) in [("m.nope();", "nope"), ("", "no sound"), ("m.key('H minor');", "Unknown key")] {
            do {
                try await MusicRenderer.render(MusicSource(score: .code(score), options: MusicRenderOptions(duration: 2)), to: url)
                XCTFail("'\(score)' should fail")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testOptionsAreChecked() {
        let invalid = [
            MusicRenderOptions(duration: 601), MusicRenderOptions(duration: 10, bpm: 500),
            MusicRenderOptions(duration: 10, intensity: 2),
        ]
        for options in invalid {
            XCTAssertThrowsError(try MusicRenderer.validate(MusicSource(score: .style(.ambient), options: options)))
        }
    }

    func testASourceSurvivesItsSidecar() throws {
        let url = tempURL()
        let source = MusicSource(score: .code("m.bell('A4', 0);"), options: MusicRenderOptions(duration: 5, seed: 4, key: "D dorian"))
        defer { RenderedAssets.remove(url) }
        try source.save(for: url)
        XCTAssertEqual(MusicSource.load(for: url), source)
    }

    func testRenderedNamesAreExact() {
        XCTAssertTrue(RenderedAssets.isRendered(RenderedAssets.newFileName(.music), as: .music))
        XCTAssertFalse(RenderedAssets.isRendered("music-intro.m4a", as: .music))
        XCTAssertFalse(RenderedAssets.isRendered(RenderedAssets.newFileName(.motion), as: .music))
    }
}
