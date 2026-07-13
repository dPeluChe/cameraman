import AVFoundation
import XCTest
@testable import EngineKit

final class VoiceoverRecorderTests: XCTestCase {
    func testWriterFlushesEveryQueuedBufferBeforeFinishReturns() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceover-writer-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let writer = VoiceoverAudioWriter(file: file)
        let framesPerBuffer: AVAudioFrameCount = 1_024
        let bufferCount = 32

        for _ in 0..<bufferCount {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesPerBuffer
            ))
            buffer.frameLength = framesPerBuffer
            writer.enqueue(buffer)
        }

        try await writer.finish()

        let recorded = try AVAudioFile(forReading: url)
        XCTAssertEqual(recorded.length, AVAudioFramePosition(framesPerBuffer) * Int64(bufferCount))
    }
}
