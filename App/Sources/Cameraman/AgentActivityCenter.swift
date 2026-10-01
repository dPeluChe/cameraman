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
    /// Quiet time after the last agent edit before the editor takes control back.
    private let idleDelay: Duration

    @Published private(set) var activeProjects: Set<ProjectId> = []

    private var idleTasks: [ProjectId: Task<Void, Never>] = [:]
    private var flushers: [ProjectId: () async -> Void] = [:]

    init(idleDelay: Duration = .seconds(3)) { self.idleDelay = idleDelay }

    /// The open editor registers how to persist its unsaved changes.
    func registerFlusher(for projectId: ProjectId, _ flush: @escaping () async -> Void) {
        flushers[projectId] = flush
    }

    /// Called before an agent edit reads the project from disk.
    func agentWillEdit(_ projectId: ProjectId) async {
        markActive(projectId)          // freeze first so no new edit slips in during the flush
        await flushers[projectId]?()
    }

    /// Called after each agent edit; keeps the freeze alive while the agent keeps working.
    func agentDidEdit(_ projectId: ProjectId) {
        markActive(projectId)
    }

    private func markActive(_ projectId: ProjectId) {
        activeProjects.insert(projectId)
        idleTasks[projectId]?.cancel()
        idleTasks[projectId] = Task { [weak self] in
            try? await Task.sleep(for: idleDelay)
            guard !Task.isCancelled, let self else { return }
            self.activeProjects.remove(projectId)
            self.idleTasks[projectId] = nil
            // One reload for the whole burst; the editor already debounces this.
            NotificationCenter.default.post(name: .projectUpdated, object: projectId)
        }
    }
}
