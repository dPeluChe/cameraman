import XCTest
@testable import EngineKit

final class CaptureStreamStopTests: XCTestCase {
    private struct Boom: LocalizedError { var errorDescription: String? { "display disconnected" } }

    func testDelegateReportsAStreamStoppedBySystem() {
        var received: Error?
        let delegate = StreamDelegate { received = $0 }
        delegate.handleStop(Boom())
        XCTAssertEqual(received?.localizedDescription, "display disconnected")
    }

    func testEngineAnnouncesTheStopWithAReadableReason() {
        let expectation = expectation(forNotification: CaptureEngine.streamStoppedNotification, object: nil) { note in
            note.userInfo?["reason"] as? String == "display disconnected"
        }
        CaptureEngine.postStreamStopped(Boom())
        wait(for: [expectation], timeout: 1)
    }
}
