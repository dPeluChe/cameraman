import XCTest
import EngineKit
@testable import Cameraman

@MainActor
final class AgentActivityCenterTests: XCTestCase {
    func testAgentEditFreezesFlushesThenReleasesWhenQuiet() async throws {
        let center = AgentActivityCenter(editHold: .milliseconds(150), idleAfterEdit: .milliseconds(150))
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

        // Quiet: the editor is asked to reload and stays frozen until it confirms.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(center.activeProjects.contains(id), "frozen until the reload lands")
        center.reloadFinished(id)
        XCTAssertFalse(center.activeProjects.contains(id), "released once the reload finished")
    }

    func testProjectWithNoOpenEditorIsFreedWithoutAReload() async throws {
        let center = AgentActivityCenter(editHold: .milliseconds(100), idleAfterEdit: .milliseconds(100))
        let id = ProjectId()
        center.agentDidEdit(id)          // no flusher registered: nobody to reload
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(center.activeProjects.contains(id))
    }

    func testContinuedAgentEditsKeepTheFreezeAlive() async throws {
        let center = AgentActivityCenter(editHold: .milliseconds(200), idleAfterEdit: .milliseconds(200))
        let id = ProjectId()
        for _ in 0..<4 {
            center.agentDidEdit(id)
            try await Task.sleep(for: .milliseconds(100)) // shorter than the idle delay
        }
        XCTAssertTrue(center.activeProjects.contains(id))
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(center.activeProjects.contains(id)) // no editor open, so freed at idle
    }

    func testOtherProjectsAreUnaffected() async {
        let center = AgentActivityCenter(editHold: .seconds(5), idleAfterEdit: .seconds(5))
        let editing = ProjectId(), other = ProjectId()
        await center.agentWillEdit(editing)
        XCTAssertFalse(center.activeProjects.contains(other))
    }

    func testFlushAllEditorsSavesEveryOpenEditor() async {
        let center = AgentActivityCenter()
        var saved: Set<ProjectId> = []
        let a = ProjectId(), b = ProjectId()
        center.registerFlusher(for: a) { saved.insert(a) }
        center.registerFlusher(for: b) { saved.insert(b) }
        await center.flushAllEditors()
        XCTAssertEqual(saved, [a, b])
    }

    /// Quit must never hang on a save that does not return.
    func testFlushAllEditorsGivesUpOnAStuckSave() async {
        let center = AgentActivityCenter()
        center.registerFlusher(for: ProjectId()) { try? await Task.sleep(for: .seconds(30)) }
        let started = Date()
        await center.flushAllEditors(timeout: .milliseconds(200))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
