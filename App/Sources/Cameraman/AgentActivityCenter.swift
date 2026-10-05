//
//  AgentActivityCenter.swift
//  App
//
//  Tracks which projects an AI agent (via the in-app MCP server) is editing. An agent edits
//  far faster than a person, so it has priority: the editor for that project freezes behind
//  a notice, unsaved work is flushed first so the agent starts from it, and one reload
//  happens when the agent has been quiet for a few seconds.
//

import Combine
import EngineKit
import Foundation

@MainActor
final class AgentActivityCenter: ObservableObject {
    static let shared = AgentActivityCenter()

    @Published private(set) var activeProjects: Set<ProjectId> = []

    /// Safety net while an edit is in flight: long enough for a slow one (asset staging), and
    /// the only thing that frees the project if the edit fails and no "did edit" ever comes.
    private let editHold: Duration
    /// Quiet time after the last edit. LLM turns often pause longer than a few seconds.
    private let idleAfterEdit: Duration

    private var timers: [ProjectId: Task<Void, Never>] = [:]
    private var flushers: [ProjectId: () async -> Void] = [:]
    private var awaitingReload: Set<ProjectId> = []

    init(editHold: Duration = .seconds(10), idleAfterEdit: Duration = .seconds(5)) {
        self.editHold = editHold
        self.idleAfterEdit = idleAfterEdit
    }

    /// The open editor registers how to persist its unsaved changes.
    func registerFlusher(for projectId: ProjectId, _ flush: @escaping () async -> Void) {
        flushers[projectId] = flush
    }

    /// Persist every open editor's unsaved work. Used on quit; bounded so a stuck save cannot
    /// keep the app from exiting.
    func flushAllEditors(timeout: Duration = .seconds(3)) async {
        let pending = Array(flushers.values)
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await Task.sleep(for: timeout) }
            group.addTask { await withTaskGroup(of: Void.self) { inner in
                for flush in pending { inner.addTask { await flush() } }
            } }
            await group.next()      // first to finish: all saved, or the timeout
            group.cancelAll()
        }
    }

    /// Called before an agent edit reads the project from disk.
    func agentWillEdit(_ projectId: ProjectId) async {
        markActive(projectId, quietFor: editHold)  // freeze first so nothing new slips in during the flush
        await flushers[projectId]?()
    }

    /// Called after each agent edit; keeps the freeze alive while the agent keeps working.
    func agentDidEdit(_ projectId: ProjectId) {
        markActive(projectId, quietFor: idleAfterEdit)
    }

    /// The editor finished reloading from disk: it is safe to hand control back.
    func reloadFinished(_ projectId: ProjectId) {
        release(projectId)
    }

    private func markActive(_ projectId: ProjectId, quietFor delay: Duration) {
        activeProjects.insert(projectId)
        awaitingReload.remove(projectId)  // new agent activity cancels a pending hand-back
        timers[projectId]?.cancel()
        timers[projectId] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.timers[projectId] = nil
            self.requestReload(projectId)
        }
    }

    /// Agent went quiet: reload the editor once, and stay frozen until it confirms. With no
    /// editor open there is nothing to reload, so the project is freed at once; the fallback
    /// frees it if the reload never reports back.
    private func requestReload(_ projectId: ProjectId) {
        guard flushers[projectId] != nil else { activeProjects.remove(projectId); return }
        awaitingReload.insert(projectId)
        NotificationCenter.default.post(name: .projectUpdated, object: projectId)
        timers[projectId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            self.timers[projectId] = nil
            self.release(projectId)
        }
    }

    private func release(_ projectId: ProjectId) {
        guard awaitingReload.remove(projectId) != nil else { return }
        timers[projectId]?.cancel()
        timers[projectId] = nil
        activeProjects.remove(projectId)
    }
}
