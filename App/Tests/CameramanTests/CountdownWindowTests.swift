import XCTest
import AppKit
@testable import Cameraman

@MainActor
final class CountdownWindowTests: XCTestCase {
    func testNoTimerReturnsImmediately() async {
        let started = Date()
        let go = await CountdownWindow().run(seconds: 0)
        XCTAssertTrue(go)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
    }

    func testCountsDownThenAllowsRecording() async {
        _ = NSApplication.shared
        let started = Date()
        let go = await CountdownWindow().run(seconds: 1)
        XCTAssertTrue(go)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.9)
    }

    func testEscapeCancelsTheCountdown() async throws {
        _ = NSApplication.shared
        let window = CountdownWindow()
        let result = Task { await window.run(seconds: 5) }
        try await Task.sleep(for: .milliseconds(300))
        let panel = try XCTUnwrap(NSApp.windows.first { $0.level == .screenSaver })
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        panel.keyDown(with: esc)
        let go = await result.value
        XCTAssertFalse(go, "Esc must cancel instead of starting the recording")
    }
}
