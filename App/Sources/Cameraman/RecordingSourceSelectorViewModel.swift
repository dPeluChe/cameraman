//
//  RecordingSourceSelectorViewModel.swift
//  App
//
//  Extracted from RecordingSourceSelectorView.swift
//  View model and display highlighter for source selection
//

import AppKit
import Combine
import EngineKit
import SwiftUI

// MARK: - View Model

@MainActor
class SourceSelectorViewModel: ObservableObject {
    enum SourceTab {
        case display, window, application
    }

    @Published var selectedTab: SourceTab = .display
    @Published var displaySources: [SourceSelector.DisplaySource] = []
    @Published var windowSources: [SourceSelector.WindowSource] = []
    @Published var applicationSources: [SourceSelector.ApplicationSource] = []
    @Published var previewImage: NSImage?
    @Published var errorMessage: String?
    @Published var permissionDenied = false

    private let sourceSelector = SourceSelector.shared
    private let permissionManager = PermissionManager.shared

    func loadSources(for tab: SourceTab) async {
        errorMessage = nil
        previewImage = nil
        permissionDenied = false

        do {
            switch tab {
            case .display:
                displaySources = try await sourceSelector.listDisplays()

                let status = await permissionManager.checkScreenRecordingPermission()
                if status != .authorized {
                    print("Screen recording permission missing, capture will fail")
                }

            case .window:
                windowSources = try await sourceSelector.listWindows()

            case .application:
                applicationSources = try await sourceSelector.listApplications()
            }
        } catch {
            if let selectorError = error as? SourceSelector.SourceSelectorError,
               case .permissionDenied = selectorError {
                permissionDenied = true
                errorMessage = "Screen recording permission denied."
            } else {
                let nsError = error as NSError
                if nsError.domain.contains("SCStreamError") && nsError.code == -3801 {
                    permissionDenied = true
                    errorMessage = "Screen recording permission denied."
                } else {
                    errorMessage = "Failed to load sources: \(error.localizedDescription)"
                }
            }
            print("Error loading sources: \(error)")
        }
    }

    func openSystemSettings() async {
        _ = await permissionManager.requestScreenRecordingPermission()
    }

    func capturePreview(display: SourceSelector.DisplaySource) async {
        await MainActor.run {
            DisplayHighlighter.shared.toggleHighlight(displayID: display.id)
        }

        self.previewImage = NSImage(systemSymbolName: "display", accessibilityDescription: "Display Preview")
    }

    func capturePreview(window: SourceSelector.WindowSource) async {
        self.previewImage = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Window Preview")
    }

    private func captureScreenshot(displayID: String? = nil, windowID: String? = nil) async {
        // Deprecated helper, functionality moved to specific methods
    }
}

// MARK: - Display Highlighter

@MainActor
class DisplayHighlighter {
    static let shared = DisplayHighlighter()
    private var highlightWindow: NSWindow?
    private var currentDisplayID: String?
    private var cleanupTask: Task<Void, Never>?

    private init() {}

    func toggleHighlight(displayID: String) {
        if currentDisplayID == displayID {
            stopHighlight()
            return
        }

        stopHighlight()

        guard let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return String(id.uint32Value) == displayID
        }) else {
            print("Could not find screen for ID: \(displayID)")
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .stationary]
        window.isReleasedWhenClosed = false

        let view = NSBox(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.boxType = .custom
        view.isTransparent = true
        view.fillColor = .clear

        view.wantsLayer = true
        view.layer?.borderWidth = 20
        view.layer?.borderColor = NSColor.red.cgColor

        window.contentView = view

        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()

        highlightWindow = window
        currentDisplayID = displayID

        cleanupTask = Task {
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    self.stopHighlight()
                }
            }
        }
    }

    func stopHighlight() {
        cleanupTask?.cancel()
        cleanupTask = nil

        if let window = highlightWindow {
            window.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.close()
            }
            highlightWindow = nil
        }
        currentDisplayID = nil
    }
}
