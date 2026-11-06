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
            let seconds = try await MusicRenderer.render(score: .style(style), to: url, options: MusicRenderOptions(duration: 6))
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
            try await MusicRenderer.render(score: .style(.acoustic), to: url, options: MusicRenderOptions(duration: 3, seed: seed))
        }
        let (first, same, other) = (try samples(of: urls[0]), try samples(of: urls[1]), try samples(of: urls[2]))
        let difference = { (a: [Float], b: [Float]) in zip(a, b).map { abs($0 - $1) }.max() ?? 1 }
        XCTAssertLessThan(difference(first, same), 0.0001)
        XCTAssertGreaterThan(difference(first, other), 0.01)
    }

    func testVoicesOutliveTheSchedulingWindows() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let score = "m.pluck('A3', 9.5, { vel: 1 });"
        try await MusicRenderer.render(score: .code(score), to: url, options: MusicRenderOptions(duration: 12))
        let audio = try samples(of: url)
        XCTAssertEqual(audio[..<(48_000 * 9)].map(abs).max() ?? 1, 0, accuracy: 0.001, "nothing before the note")
        XCTAssertGreaterThan(audio[(48_000 * 9 + 24_000)...].map(abs).max() ?? 0, 0.1, "a note in a later window must play")
    }

    func testScoreErrorsReachTheCaller() async {
        let url = tempURL()
        for (score, expected) in [("m.nope();", "nope"), ("", "no sound"), ("m.key('H minor');", "Unknown key")] {
            do {
                try await MusicRenderer.render(score: .code(score), to: url, options: MusicRenderOptions(duration: 2))
                XCTFail("'\(score)' should fail")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testLengthIsBounded() async {
        do {
            try await MusicRenderer.render(score: .style(.ambient), to: tempURL(), options: MusicRenderOptions(duration: 601))
            XCTFail("over the limit")
        } catch { XCTAssertTrue(error is MusicError) }
    }

    func testRenderedNamesAreExact() {
        XCTAssertTrue(RenderedAssets.isRendered(RenderedAssets.newFileName(.music), as: .music))
        XCTAssertFalse(RenderedAssets.isRendered("music-intro.m4a", as: .music))
        XCTAssertFalse(RenderedAssets.isRendered(RenderedAssets.newFileName(.motion), as: .music))
    }
}
