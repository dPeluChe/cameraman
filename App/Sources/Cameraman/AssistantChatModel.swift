//
//  AssistantChatModel.swift
//  Cameraman
//
//  The AI Assistant tool: a chat with the user's own agent (Claude Code), which edits the open project
//  through the in-app MCP server. Lives with the editor view model, so collapsing the tool keeps the chat.
//

import Combine
import EngineKit
import Foundation

@MainActor
final class AssistantChatModel: ObservableObject {
    enum Role { case user, assistant, notice }

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        var tools: [Tool] = []
    }

    struct Tool: Identifiable {
        enum State { case running, done, failed }
        let id: String
        let name: String
        var state = State.running
    }

    enum Availability: Equatable { case checking, ready, missing }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isRunning = false
    @Published private(set) var availability = Availability.checking
    /// What the last turn cost at API rates; on a subscription it comes out of the plan's Agent SDK credit.
    @Published private(set) var lastCost: Double?

    private let projectId: ProjectId
    private let projectName: () -> String
    private var backend: ClaudeCodeBackend?
    private var session: String?
    private var turn: Task<Void, Never>?

    init(projectId: ProjectId, projectName: @escaping () -> String) {
        self.projectId = projectId
        self.projectName = projectName
    }

    func locate() async {
        guard backend == nil else { return }
        availability = .checking
        backend = await ClaudeCodeBackend.locate().map { ClaudeCodeBackend(executable: $0) }
        availability = backend == nil ? .missing : .ready
    }

    func send(_ prompt: String) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning, let backend else { return }
        messages.append(Message(role: .user, text: prompt))
        messages.append(Message(role: .assistant, text: ""))
        isRunning = true
        lastCost = nil
        turn = Task { [weak self] in
            await self?.run(prompt, on: backend)
            self?.isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        turn?.cancel()
        messages.append(Message(role: .notice, text: "Stopped."))
    }

    func newChat() {
        stop()
        messages = []
        session = nil
        lastCost = nil
    }

    private func run(_ prompt: String, on backend: ClaudeCodeBackend) async {
        guard let server = await MCPHostService.shared.ensureRunning() else {
            return fail("Cameraman's built-in server could not start: port \(MCPHostService.defaultPort) is in use.")
        }
        let context = AgentContext(mcpEndpoint: server.endpoint, mcpToken: server.token, instructions: instructions)
        for await event in backend.send(prompt, session: session, context: context) {
            apply(event)
        }
        if messages.last?.role == .assistant, messages.last?.text.isEmpty == true, messages.last?.tools.isEmpty == true {
            messages.removeLast()
        }
    }

    private func apply(_ event: AgentEvent) {
        switch event {
        case .started(let id):
            session = id
        case .text(let piece):
            updateReply { $0.text += piece }
        case .toolStarted(let id, let name):
            updateReply { $0.tools.append(Tool(id: id, name: Self.title(of: name))) }
        case .toolFinished(let id, let failed):
            updateReply { reply in
                if let index = reply.tools.firstIndex(where: { $0.id == id }) { reply.tools[index].state = failed ? .failed : .done }
            }
        case .finished(let cost):
            lastCost = cost
        case .failed(let reason):
            fail(Self.explain(reason))
        }
    }

    private func updateReply(_ change: (inout Message) -> Void) {
        guard let index = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        change(&messages[index])
    }

    private func fail(_ text: String) {
        messages.append(Message(role: .notice, text: text))
    }

    private var instructions: String {
        """
        You are the assistant inside Cameraman, a macOS screen recording and video editor. The user has the project \
        "\(projectName())" open, projectId \(projectId.uuidString). Work on it with the cameraman tools and always pass \
        that projectId. Read the project (and its captions when the request is about what is said) before editing. \
        The editor shows your edits when you finish. Reply in the user's language, briefly, and say what you changed.
        """
    }

    /// "mcp__cameraman__add_music" reads "add music".
    static func title(of tool: String) -> String {
        (tool.components(separatedBy: "__").last ?? tool).replacingOccurrences(of: "_", with: " ")
    }

    private static func explain(_ reason: String) -> String {
        let lowered = reason.lowercased()
        if lowered.contains("login") || lowered.contains("log in") || lowered.contains("authenticat") {
            return "Claude Code is not signed in. Run `claude auth login` in Terminal, then try again."
        }
        return reason
    }
}
