//
//  AssistantChatModel.swift
//  Cameraman
//
//  The AI Assistant tool: one chat for the whole app with the user's own agent (Claude Code), which edits
//  projects through the in-app MCP server. It outlives the editor, so switching projects keeps the chat.
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

    static let shared = AssistantChatModel()

    /// The project in the editor, told to the agent on every turn.
    private var openProject: () -> (id: ProjectId, name: String)? = { nil }
    private var backend: (any AgentBackend)?
    private var session: String?
    private var turn: Task<Void, Never>?
    /// Deltas land here and reach `messages` at most every 80 ms, so a fast stream does not re-render per token.
    private var pendingText = ""
    private var flush: Task<Void, Never>?
    private init() {}

    func follow(_ project: @escaping () -> (id: ProjectId, name: String)?) {
        openProject = project
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

    private func run(_ prompt: String, on backend: any AgentBackend) async {
        guard let server = await MCPHostService.shared.ensureRunning() else {
            return fail("Cameraman's built-in server could not start: port \(MCPHostService.defaultPort) is in use.")
        }
        let context = AgentContext(mcpEndpoint: server.endpoint, mcpToken: server.token, instructions: instructions)
        for await event in backend.send(prompt, session: session, context: context) {
            apply(event)
        }
        flushText()
    }

    private func apply(_ event: AgentEvent) {
        switch event {
        case .started(let id):
            session = id
        case .text(let piece):
            pendingText += piece
            if flush == nil {
                flush = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    self?.flushText()
                }
            }
        case .toolStarted(let id, let name):
            flushText()
            updateReply { $0.tools.append(Tool(id: id, name: Self.title(of: name))) }
        case .toolFinished(let id, let failed):
            updateReply { reply in
                if let index = reply.tools.firstIndex(where: { $0.id == id }) { reply.tools[index].state = failed ? .failed : .done }
            }
        case .finished(let cost):
            lastCost = cost
        case .failed(let reason):
            flushText()
            fail(reason)
        }
    }

    private func flushText() {
        flush?.cancel()
        flush = nil
        guard !pendingText.isEmpty else { return }
        let text = pendingText
        pendingText = ""
        updateReply { $0.text += text }
    }

    /// The reply of the current turn, created on its first text or tool.
    private func updateReply(_ change: (inout Message) -> Void) {
        if messages.last?.role != .assistant { messages.append(Message(role: .assistant, text: "")) }
        change(&messages[messages.count - 1])
    }

    private func fail(_ text: String) {
        messages.append(Message(role: .notice, text: text))
    }

    private var instructions: String {
        var text = """
            You are the assistant inside Cameraman. This is one chat for the whole app, so the user may talk about \
            any of their projects. Work with the cameraman tools (their server instructions say how).
            Only take on work in Cameraman: editing and organizing projects, cuts, layout, motions (their HTML \
            included), music, subtitles, recording and export. For anything else, such as writing code for \
            another app or general questions, do not do it: say in one line that this chat is for editing in \
            Cameraman and suggest what you can do with their video instead.
            """
        if let project = openProject() {
            text += " The editor has \"\(project.name)\" open, projectId \(project.id.uuidString): \"this video\" means it."
        } else {
            text += " No project is open in the editor; find projects with list_projects."
        }
        return text
    }

    /// "mcp__cameraman__add_music" reads "add music".
    static func title(of tool: String) -> String {
        (tool.components(separatedBy: "__").last ?? tool).replacingOccurrences(of: "_", with: " ")
    }
}
