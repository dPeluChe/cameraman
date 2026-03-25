//
//  ScreenAreaSelector.swift
//  App
//
//  Full-screen transparent overlay that lets the user drag-select a recording area.
//  The selection rect is returned in display points (top-left origin), ready for
//  SCStreamConfiguration.sourceRect.
//

import AppKit
import SwiftUI
import EngineKit

// MARK: - Controller

/// Borderless NSPanel subclass that allows key window status so keyboard shortcuts work.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
class ScreenAreaSelectorController {
    static let shared = ScreenAreaSelectorController()

    private var window: NSPanel?

    private init() {}

    /// Show the area selector overlay on the display matching `displaySource`.
    /// Calls `completion` with the selected CGRect in display points (top-left origin),
    /// or nil if the user cancelled.
    func show(for displaySource: SourceSelector.DisplaySource, completion: @escaping (CGRect?) -> Void) {
        // Close any previously open panel before creating a new one
        window?.close()
        window = nil

        guard let screen = NSScreen.screen(withDisplayID: displaySource.id) else { return }

        let panel = KeyablePanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let view = ScreenAreaSelectorView(
            screenSize: screen.frame.size,
            onConfirm: { [weak self] rect in
                self?.window?.close()
                self?.window = nil
                completion(rect)
            },
            onCancel: { [weak self] in
                self?.window?.close()
                self?.window = nil
                completion(nil)
            }
        )

        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        self.window = panel
    }
}

// MARK: - SwiftUI View

struct ScreenAreaSelectorView: View {
    let screenSize: CGSize
    let onConfirm: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil

    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent,
              abs(current.x - start.x) > 4, abs(current.y - start.y) > 4 else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var body: some View {
        // Compute once per render — used in overlay, border, handles, and dimension label
        let rect = selectionRect

        return ZStack(alignment: .top) {
            overlayLayer(rect)

            VStack(spacing: 0) {
                instructionBar(hasSelection: rect != nil)
                Spacer()
                if let r = rect {
                    dimensionLabel(r).padding(.bottom, 24)
                }
            }

            // White selection border and corner handles (outside compositingGroup so they are not cut out)
            if let r = rect {
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                cornerHandles(for: r)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { value in
                    if dragStart == nil { dragStart = value.startLocation }
                    dragCurrent = value.location
                }
        )
        .onTapGesture(count: 2) {
            if let r = selectionRect { onConfirm(r) }
        }
        .onAppear { NSCursor.crosshair.set() }
        .onDisappear { NSCursor.arrow.set() }
    }

    // MARK: - Subviews

    private func overlayLayer(_ selection: CGRect?) -> some View {
        Color.black.opacity(0.5)
            .overlay(
                Group {
                    if let r = selection {
                        Rectangle()
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .blendMode(.destinationOut)
                    }
                }
            )
            .compositingGroup()
            .frame(width: screenSize.width, height: screenSize.height)
    }

    private func instructionBar(hasSelection: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "selection.pin.in.out")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))

            if hasSelection {
                Text("Double-click to confirm")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                Text("Drag to select recording area")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }

            Spacer()

            Button("Cancel") { onCancel() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func dimensionLabel(_ rect: CGRect) -> some View {
        Text("\(Int(rect.width)) × \(Int(rect.height))")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.65))
            .cornerRadius(6)
    }

    // Decorative corner handles (8×8 white squares at each corner of the selection)
    private func cornerHandles(for rect: CGRect) -> some View {
        let size: CGFloat = 8
        let corners: [(CGFloat, CGFloat)] = [
            (rect.minX, rect.minY), (rect.maxX, rect.minY),
            (rect.minX, rect.maxY), (rect.maxX, rect.maxY)
        ]
        return ForEach(corners.indices, id: \.self) { i in
            Rectangle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .position(x: corners[i].0, y: corners[i].1)
        }
    }
}

// MARK: - Area Highlight Controller

/// Shows a persistent overlay indicating the currently selected capture area.
@MainActor
class AreaHighlightController {
    static let shared = AreaHighlightController()
    private var window: NSWindow?

    private init() {}

    func show(rect: CGRect, on displaySource: SourceSelector.DisplaySource) {
        hide()
        guard let screen = NSScreen.screen(withDisplayID: displaySource.id) else { return }

        let overlayWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.level = .statusBar
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .stationary]
        overlayWindow.isReleasedWhenClosed = false
        // Must be .none so the overlay is not captured in screen recordings
        overlayWindow.sharingType = .none

        let view = AreaHighlightView(selectedRect: rect, screenSize: screen.frame.size)
        overlayWindow.contentView = NSHostingView(rootView: view)
        overlayWindow.setFrame(screen.frame, display: true)
        overlayWindow.orderFrontRegardless()
        window = overlayWindow
    }

    func hide() {
        if let w = window {
            w.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { w.close() }
            window = nil
        }
    }
}

// MARK: - Area Highlight View

struct AreaHighlightView: View {
    let selectedRect: CGRect
    let screenSize: CGSize

    var body: some View {
        ZStack {
            // Subtle darkening outside the selected area
            Color.black.opacity(0.2)
                .overlay(
                    Rectangle()
                        .frame(width: selectedRect.width, height: selectedRect.height)
                        .position(x: selectedRect.midX, y: selectedRect.midY)
                        .blendMode(.destinationOut)
                )
                .compositingGroup()

            // Dashed red border around the selected area
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                .foregroundStyle(Color.red)
                .frame(width: selectedRect.width, height: selectedRect.height)
                .position(x: selectedRect.midX, y: selectedRect.midY)

            // Dimensions label below the selection
            Text("\(Int(selectedRect.width)) × \(Int(selectedRect.height))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.65))
                .cornerRadius(5)
                .position(x: selectedRect.midX, y: selectedRect.maxY + 20)
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}
