//
//  TeleprompterWindow.swift
//  App
//
//  Floating teleprompter window excluded from screen capture.
//  Shows scrolling text overlay for reading while recording.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Teleprompter Window Controller

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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Teleprompter"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        // Exclude from screen capture (ScreenCaptureKit won't record this window)
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
        window?.close()
        window = nil
        hostingView = nil
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    /// Get the NSWindow reference for SCContentFilter exclusion
    var nsWindow: NSWindow? { window }
}

// MARK: - Teleprompter ViewModel

@MainActor
class TeleprompterViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fontSize: CGFloat = 28
    @Published var scrollSpeed: Double = 30 // pixels per second
    @Published var isScrolling: Bool = false
    @Published var scrollOffset: CGFloat = 0

    private var scrollTimer: Timer?

    func startScrolling() {
        guard !isScrolling else { return }
        isScrolling = true
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isScrolling else { return }
                self.scrollOffset += CGFloat(self.scrollSpeed / 30.0)
            }
        }
    }

    func stopScrolling() {
        isScrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    func resetScroll() {
        stopScrolling()
        scrollOffset = 0
    }

    func toggleScrolling() {
        if isScrolling { stopScrolling() } else { startScrolling() }
    }
}

// MARK: - Teleprompter Overlay View

struct TeleprompterOverlayView: View {
    @ObservedObject var viewModel: TeleprompterViewModel
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack(spacing: 10) {
                Button {
                    viewModel.toggleScrolling()
                } label: {
                    Image(systemName: viewModel.isScrolling ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    viewModel.resetScroll()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                // Font size
                HStack(spacing: 4) {
                    Text("A")
                        .font(.system(size: 10))
                    Slider(value: $viewModel.fontSize, in: 16...60, step: 2)
                        .frame(width: 80)
                    Text("A")
                        .font(.system(size: 16))
                }

                // Speed
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.bottom.0percent")
                        .font(.system(size: 10))
                    Slider(value: $viewModel.scrollSpeed, in: 10...100, step: 5)
                        .frame(width: 80)
                    Image(systemName: "gauge.with.dots.needle.bottom.100percent")
                        .font(.system(size: 10))
                }

                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "eye" : "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))

            // Content
            if isEditing {
                TextEditor(text: $viewModel.text)
                    .font(.system(size: viewModel.fontSize))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .padding(16)
            } else {
                // Scrolling prompter view
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(viewModel.text.isEmpty ? "Paste your script here..." : viewModel.text)
                            .font(.system(size: viewModel.fontSize, weight: .medium))
                            .foregroundStyle(viewModel.text.isEmpty ? .white.opacity(0.3) : .white)
                            .lineSpacing(viewModel.fontSize * 0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .offset(y: -viewModel.scrollOffset)
                }
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditing = true
                }
            }
        }
        .frame(minWidth: 400, minHeight: 150)
    }
}
