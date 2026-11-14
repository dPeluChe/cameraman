//
//  AssistantChatView.swift
//  Cameraman
//
//  The app-wide assistant: a panel docked beside the editor or floating over it. See AssistantChatModel.
//

import SwiftUI

struct AssistantPanel: View {
    @ObservedObject var model: AssistantChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Label("Assistant", systemImage: "sparkles").font(.headline)
                Spacer()
                Menu {
                    Button("New Chat", action: model.newChat).disabled(model.isRunning || model.messages.isEmpty)
                    Picker("Placement", selection: $model.placement) {
                        Text("Docked on the Right").tag(AssistantChatModel.Placement.docked)
                        Text("Floating").tag(AssistantChatModel.Placement.floating)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Use Another App Instead (MCP)…") { Self.openSettings() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button { model.isPresented = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("Hide (⌘J)")
            }
            AssistantChatView(model: model)
        }
        .padding(Spacing.md)
    }

    /// Settings → Developer explains connecting other agents (selector name differs across macOS versions).
    private static func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

struct AssistantChatView: View {
    @ObservedObject var model: AssistantChatModel

    @State private var draft = ""
    private static let bottom = "bottom"

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
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await model.locate() }
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("The assistant runs Claude Code with your own Claude plan.")
                .font(.caption)
            Text("Install it from claude.com/code, run `claude auth login` in Terminal, then reopen this panel.")
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
                        MessageRow(message: message, isStreaming: model.isRunning && message.id == model.messages.last?.id)
                            .id(message.id)
                    }
                    if model.isRunning {
                        ProgressView().controlSize(.small).id(Self.bottom)
                    }
                }
                .padding(Spacing.xs)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.medium).fill(AppColor.inset))
            .onChangeCompat(of: model.messages.last?.text.count) { _ in
                if model.isRunning { proxy.scrollTo(Self.bottom, anchor: .bottom) }
                else if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
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
    /// Plain text while it streams; Markdown is parsed once the reply is complete.
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.callout)
                .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Color.accentColor.opacity(0.15)))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        case .assistant:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(message.tools) { tool in
                    Label(tool.name, systemImage: icon(tool.state))
                        .font(.caption).foregroundStyle(tool.state == .failed ? Color.red : .secondary)
                }
                if isStreaming {
                    Text(verbatim: message.text).font(.callout)
                } else if !message.text.isEmpty {
                    Text(LocalizedStringKey(message.text)).font(.callout).textSelection(.enabled)
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
