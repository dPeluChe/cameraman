//
//  TeleprompterWindow.swift
//  App
//
//  Floating teleprompter window excluded from screen capture.
//  Two tabs: Edit (text only) and Preview (controls + playback).
//  Two preview modes: Scroll (continuous) and Paragraph (block by block).
//

import SwiftUI
import AppKit
import Combine

// MARK: - Window Controller

@MainActor
class TeleprompterWindowController {
    static let shared = TeleprompterWindowController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<TeleprompterOverlayView>?
    let viewModel = TeleprompterViewModel()

    var text: String {
        get { viewModel.text }
        set { viewModel.text = newValue }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 280),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Teleprompter"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none

        let contentView = TeleprompterOverlayView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: contentView)
        panel.contentView = hosting

        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.window = panel
        self.hostingView = hosting
    }

    func hide() {
        viewModel.pause()
        window?.close()
        window = nil
        hostingView = nil
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

}

// MARK: - Types

enum TeleprompterMode: String, CaseIterable {
    case scroll = "Scroll"
    case paragraph = "Paragraph"
}

enum TeleprompterTab: String, CaseIterable {
    case edit = "Edit"
    case preview = "Preview"
}

// MARK: - ViewModel (moved to TeleprompterViewModel.swift)

// MARK: - Main View

struct TeleprompterOverlayView: View {
    @ObservedObject var viewModel: TeleprompterViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            // Content
            switch viewModel.tab {
            case .edit:
                editTab
            case .preview:
                previewTab
            }
        }
        .frame(minWidth: 400, minHeight: 150)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TeleprompterTab.allCases, id: \.self) { tab in
                Button {
                    viewModel.tab = tab
                    if tab == .edit { viewModel.pause() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .edit ? "pencil" : "play.rectangle")
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: viewModel.tab == tab ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(viewModel.tab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                    .foregroundStyle(viewModel.tab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.black.opacity(0.4))
    }

    // MARK: - Edit Tab (clean, text only)

    private var editTab: some View {
        VStack(spacing: 0) {
            // Word count
            HStack {
                Spacer()
                Text("\(viewModel.words.count) words")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.trailing, 12)
                    .padding(.top, 6)
            }

            TextEditor(text: $viewModel.text)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Preview Tab (controls + playback)

    private var previewTab: some View {
        VStack(spacing: 0) {
            previewControls
            Divider().opacity(0.15)

            if viewModel.text.isEmpty {
                emptyState
            } else if viewModel.mode == .scroll {
                scrollModeView
            } else {
                paragraphModeView
            }
        }
    }

    // MARK: - Preview Controls

    private var previewControls: some View {
        HStack(spacing: 8) {
            // Play / Pause
            Button { viewModel.togglePlay() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .background(viewModel.isPlaying ? Color.orange.opacity(0.3) : Color.green.opacity(0.3))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Reset
            Button { viewModel.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 18).opacity(0.3)

            // Mode picker
            Picker("", selection: $viewModel.mode) {
                ForEach(TeleprompterMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .onChangeCompat(of: viewModel.mode) { _ in viewModel.reset() }

            Spacer()

            // Font size
            HStack(spacing: 2) {
                Text("A").font(.system(size: 9)).foregroundStyle(.tertiary)
                Slider(value: $viewModel.fontSize, in: 18...56, step: 2)
                    .frame(width: 50)
                Text("A").font(.system(size: 15)).foregroundStyle(.tertiary)
            }

            // Speed
            HStack(spacing: 2) {
                Image(systemName: "tortoise").font(.system(size: 9)).foregroundStyle(.tertiary)
                Slider(value: $viewModel.scrollSpeed, in: 10...100, step: 5)
                    .frame(width: 50)
                Image(systemName: "hare").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
    }

    // MARK: - Scroll Mode

    private var scrollModeView: some View {
        GeometryReader { _ in
            ScrollView(.vertical, showsIndicators: false) {
                HighlightedText(
                    words: viewModel.words,
                    currentIndex: viewModel.currentWordIndex,
                    fontSize: viewModel.fontSize
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .offset(y: -viewModel.scrollOffset)
        }
        .clipped()
    }

    // MARK: - Paragraph Mode

    private var paragraphModeView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Progress
            HStack {
                Text("\(viewModel.currentParagraphIndex + 1) / \(viewModel.paragraphs.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            }
            .padding(.horizontal, 24)

            // Current paragraph
            HighlightedText(
                words: viewModel.currentParagraphWords,
                currentIndex: viewModel.currentParagraphWordIndex,
                fontSize: viewModel.fontSize
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Next paragraph preview
            if viewModel.currentParagraphIndex + 1 < viewModel.paragraphs.count {
                Text(viewModel.paragraphs[viewModel.currentParagraphIndex + 1])
                    .font(.system(size: viewModel.fontSize * 0.55, weight: .medium))
                    .foregroundStyle(.white.opacity(0.15))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // Navigation
            HStack(spacing: 20) {
                Button { viewModel.prevParagraph() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.currentParagraphIndex == 0)

                Button { viewModel.nextParagraph() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.currentParagraphIndex >= viewModel.paragraphs.count - 1)
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.justify.leading")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.2))
            Text("No script yet")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
            Button("Go to Edit") { viewModel.tab = .edit }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Highlighted Text

private struct HighlightedText: View {
    let words: [String]
    let currentIndex: Int
    let fontSize: CGFloat

    var body: some View {
        words.enumerated().reduce(Text("")) { result, pair in
            let (index, word) = pair
            let separator = index == 0 ? Text("") : Text(" ")
            let wordText: Text
            if index == currentIndex {
                wordText = Text(word)
                    .foregroundColor(.yellow)
                    .font(.system(size: fontSize, weight: .bold))
            } else if index < currentIndex {
                wordText = Text(word)
                    .foregroundColor(.white.opacity(0.4))
                    .font(.system(size: fontSize, weight: .medium))
            } else {
                wordText = Text(word)
                    .foregroundColor(.white)
                    .font(.system(size: fontSize, weight: .medium))
            }
            return result + separator + wordText
        }
        .lineSpacing(fontSize * 0.5)
    }
}
