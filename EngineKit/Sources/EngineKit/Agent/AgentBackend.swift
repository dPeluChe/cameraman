//
//  AgentBackend.swift
//  EngineKit
//
//  The in-app assistant runs an agent the user already has (Claude Code first), so their own login and
//  plan pay for it. Each agent is a backend behind this interface. See docs/RESEARCH/IN_APP_AGENT_2026-11.md.
//

import Foundation

public enum AgentEvent: Equatable, Sendable {
    /// The agent's conversation id, to continue it on the next turn.
    case started(session: String)
    case text(String)
    case toolStarted(id: String, name: String)
    case toolFinished(id: String, failed: Bool)
    case finished(costUSD: Double?)
    case failed(String)
}

/// Where the agent reaches Cameraman, and what it is working on.
public struct AgentContext: Sendable {
    public var mcpEndpoint: URL
    public var mcpToken: String
    public var instructions: String

    public init(mcpEndpoint: URL, mcpToken: String, instructions: String) {
        self.mcpEndpoint = mcpEndpoint
        self.mcpToken = mcpToken
        self.instructions = instructions
    }
}

public protocol AgentBackend: Sendable {
    var name: String { get }
    /// One turn. Pass the session from `.started` to continue a conversation. Cancelling the task stops the agent.
    func send(_ prompt: String, session: String?, context: AgentContext) -> AsyncStream<AgentEvent>
}
