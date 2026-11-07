//
//  AssistantChatView.swift
//  Cameraman
//
//  The chat in the AI Assistant tool. See AssistantChatModel.
//

import SwiftUI

struct AssistantChatView: View {
    @ObservedObject var model: AssistantChatModel
    var onConnectOtherApp: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch model.availability {
            case .checking:
                HStack(spacing: Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Claude Code…").font(.caption).foregroundStyle(.secondary)
                }
            case .missing:
                missing
            case .ready:
                conversation
                composer
            }
            Button("Use another app instead (MCP)…", action: onConnectOtherApp)
                .buttonStyle(.link)
                .font(.caption)
        }
        .task { await model.locate() }
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("The assistant runs Claude Code with your own Claude plan.")
                .font(.caption)
            Text("Install it from claude.com/code, run `claude auth login` in Terminal, then reopen this tool.")
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                    if model.messages.isEmpty {
                        Text("Ask for an edit: \"add calm music\", \"cut the silences\", \"add a title card with my name\".")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.messages) { message in
                        MessageRow(message: message, isLast: message.id == model.messages.last?.id, isRunning: model.isRunning)
                            .id(message.id)
                    }
                }
                .padding(Spacing.xs)
            }
            .frame(height: 320)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .onChangeCompat(of: model.messages.last?.text) { _ in
                if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .bottom, spacing: Spacing.xs) {
                TextField("Ask Claude…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                    .disabled(model.isRunning)
                if model.isRunning {
                    Button(action: model.stop) { Image(systemName: "stop.circle.fill") }
                        .buttonStyle(.plain).help("Stop")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                        .buttonStyle(.plain).help("Send")
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .font(.title3)
            HStack {
                if let cost = model.lastCost {
                    Text(String(format: "Last reply: $%.3f of your Agent SDK credit", cost))
                        .help("Claude Code bills apps like this one to your plan's monthly Agent SDK credit, at API rates.")
                }
                Spacer()
                if !model.messages.isEmpty {
                    Button("New Chat", action: model.newChat).buttonStyle(.link).disabled(model.isRunning)
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func send() {
        model.send(draft)
        draft = ""
    }
}

private struct MessageRow: View {
    let message: AssistantChatModel.Message
    let isLast: Bool
    let isRunning: Bool

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.callout)
                .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(message.tools) { tool in
                    Label(tool.name, systemImage: icon(tool.state))
                        .font(.caption).foregroundStyle(tool.state == .failed ? Color.red : .secondary)
                }
                if !message.text.isEmpty {
                    Text(LocalizedStringKey(message.text)).font(.callout).textSelection(.enabled)
                } else if isLast && isRunning && message.tools.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        case .notice:
            Text(LocalizedStringKey(message.text)).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        }
    }

    private func icon(_ state: AssistantChatModel.Tool.State) -> String {
        switch state {
        case .running: return "ellipsis.circle"
        case .done: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }
}
