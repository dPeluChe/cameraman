import XCTest
import EngineKit
@testable import Cameraman

@MainActor
final class AgentActivityCenterTests: XCTestCase {
    func testAgentEditFreezesFlushesThenReleasesWhenQuiet() async throws {
        let center = AgentActivityCenter(idleDelay: .milliseconds(150))
        let id = ProjectId()
        var flushed = false
        var frozenDuringFlush = false
        center.registerFlusher(for: id) {
            frozenDuringFlush = center.activeProjects.contains(id)
            flushed = true
        }

        await center.agentWillEdit(id)
        XCTAssertTrue(flushed, "unsaved editor work must be saved before the agent reads from disk")
        XCTAssertTrue(frozenDuringFlush, "freeze first, so nothing new is typed during the flush")
        XCTAssertTrue(center.activeProjects.contains(id))

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(center.activeProjects.contains(id), "released after the idle delay")
    }

    func testContinuedAgentEditsKeepTheFreezeAlive() async throws {
        let center = AgentActivityCenter(idleDelay: .milliseconds(200))
        let id = ProjectId()
        for _ in 0..<4 {
            center.agentDidEdit(id)
            try await Task.sleep(for: .milliseconds(100)) // shorter than the idle delay
        }
        XCTAssertTrue(center.activeProjects.contains(id))
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(center.activeProjects.contains(id))
    }

    func testOtherProjectsAreUnaffected() async {
        let center = AgentActivityCenter(idleDelay: .seconds(5))
        let editing = ProjectId(), other = ProjectId()
        await center.agentWillEdit(editing)
        XCTAssertFalse(center.activeProjects.contains(other))
    }
}
