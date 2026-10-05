import XCTest
@testable import EngineKit

final class CaptureStreamStopTests: XCTestCase {
    private struct Boom: LocalizedError { var errorDescription: String? { "display disconnected" } }

    func testDelegateReportsAStreamStoppedBySystem() {
        let reported = expectation(description: "onStop called with the error")
        let delegate = StreamDelegate { error in
            if error.localizedDescription == "display disconnected" { reported.fulfill() }
        }
        delegate.handleStop(Boom())
        wait(for: [reported], timeout: 1)
    }

    func testEngineAnnouncesTheStopWithAReadableReason() {
        let announced = expectation(forNotification: CaptureEngine.streamStoppedNotification, object: nil) { note in
            note.userInfo?["reason"] as? String == "display disconnected"
        }
        CaptureEngine.postStreamStopped(Boom())
        wait(for: [announced], timeout: 1)
    }

    /// With no recording in progress (a stop we asked for, or a late callback), nothing is announced.
    func testNoAnnouncementWithoutAnActiveRecording() async {
        let silent = expectation(forNotification: CaptureEngine.streamStoppedNotification, object: nil)
        silent.isInverted = true
        await CaptureEngine.shared.handleStreamStopped(Boom(), sessionId: UUID())
        await fulfillment(of: [silent], timeout: 0.3)
    }
}
