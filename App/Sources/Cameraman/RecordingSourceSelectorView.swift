//
//  RecordingSourceSelectorView.swift
//  App
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-C — Recording UI (Mejoras)
//

import AVFoundation
import Combine
import ScreenCaptureKit
import SwiftUI
import EngineKit

/// Visual source selector for recording (display/window/app)
struct RecordingSourceSelectorView: View {
    @StateObject private var viewModel = SourceSelectorViewModel()
    @Binding var selectedSource: CaptureSource
    
    init(selectedSource: Binding<CaptureSource>) {
        self._selectedSource = selectedSource
        // Note: SwiftUI may call init multiple times during view lifecycle - this is normal
    }

    enum CaptureSource {
        case display(SourceSelector.DisplaySource)
        case window(SourceSelector.WindowSource)
        case application(SourceSelector.ApplicationSource)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Select Recording Source")
                .font(.headline)
                .foregroundColor(.white)

            // Source type tabs
            Picker("Source Type", selection: $viewModel.selectedTab) {
                Text("Display").tag(SourceSelectorViewModel.SourceTab.display)
                Text("Window").tag(SourceSelectorViewModel.SourceTab.window)
                Text("Application").tag(SourceSelectorViewModel.SourceTab.application)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedTab) { _, newTab in
                Task {
                    await viewModel.loadSources(for: newTab)
                }
            }

            // Source list
            ScrollView {
                LazyVStack(spacing: 8) {
                    switch viewModel.selectedTab {
                    case .display:
                        ForEach(viewModel.displaySources) { source in
                            DisplaySourceRow(
                                source: source,
                                isSelected: isSelected(source),
                                onTap: { selectDisplay(source) },
                                onPreview: { showPreview(for: source) }
                            )
                        }
                    case .window:
                        ForEach(viewModel.windowSources) { source in
                            WindowSourceRow(
                                source: source,
                                isSelected: isSelected(source),
                                onTap: { selectWindow(source) },
                                onPreview: { showPreview(for: source) }
                            )
                        }
                    case .application:
                        ForEach(viewModel.applicationSources) { source in
                            ApplicationSourceRow(
                                source: source,
                                isSelected: isSelected(source),
                                onTap: { selectApplication(source) }
                            )
                        }
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Preview section
            if viewModel.previewImage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    if let image = viewModel.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 150)
                            .cornerRadius(8)
                            .background(Color.black.opacity(0.3))
                    }
                }
            }

            // Error or Permission message
            if viewModel.permissionDenied {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    
                    Text("Permission Required")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Cameraman needs screen recording permission to capture your screen and windows.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Open System Settings") {
                        Task {
                            await viewModel.openSystemSettings()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Check Again") {
                        Task {
                            await viewModel.loadSources(for: viewModel.selectedTab)
                        }
                    }
                    .buttonStyle(.link)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
            } else if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .onAppear {
            Task {
                await viewModel.loadSources(for: .display)
            }
        }
    }

    // MARK: - Selection Helpers

    private func isSelected(_ source: SourceSelector.DisplaySource) -> Bool {
        if case .display(let selected) = selectedSource {
            return selected.id == source.id
        }
        return false
    }

    private func isSelected(_ source: SourceSelector.WindowSource) -> Bool {
        if case .window(let selected) = selectedSource {
            return selected.id == source.id
        }
        return false
    }

    private func isSelected(_ source: SourceSelector.ApplicationSource) -> Bool {
        if case .application(let selected) = selectedSource {
            return selected.id == source.id
        }
        return false
    }

    private func selectDisplay(_ source: SourceSelector.DisplaySource) {
        selectedSource = .display(source)
    }

    private func selectWindow(_ source: SourceSelector.WindowSource) {
        selectedSource = .window(source)
    }

    private func selectApplication(_ source: SourceSelector.ApplicationSource) {
        selectedSource = .application(source)
    }

    private func showPreview(for source: SourceSelector.DisplaySource) {
        Task {
            await viewModel.capturePreview(display: source)
        }
    }

    private func showPreview(for source: SourceSelector.WindowSource) {
        Task {
            await viewModel.capturePreview(window: source)
        }
    }
}

// MARK: - Source Row Views

struct DisplaySourceRow: View {
    let source: SourceSelector.DisplaySource
    let isSelected: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Display icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 44, height: 30)

                    Image(systemName: "display")
                        .foregroundColor(.blue)
                }

                // Display info
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .fontWeight(isSelected ? .semibold : .regular)

                    HStack(spacing: 8) {
                        Text("\(source.width)×\(source.height)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        Text("•")
                            .foregroundColor(.white.opacity(0.4))

                        Text("\(Int(source.refreshRate))Hz")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        if source.isMain {
                            Text("•")
                                .foregroundColor(.white.opacity(0.4))
                            Text("Main")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.3) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct WindowSourceRow: View {
    let source: SourceSelector.WindowSource
    let isSelected: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Window icon
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 36, height: 28)

                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                }

                // Window info
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fontWeight(isSelected ? .semibold : .regular)

                    HStack(spacing: 8) {
                        Text(source.applicationName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        Text("•")
                            .foregroundColor(.white.opacity(0.4))

                        Text("\(source.width)×\(source.height)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        if !source.isOnScreen {
                            Text("•")
                                .foregroundColor(.white.opacity(0.4))
                            Text("Off-screen")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(isSelected ? Color.purple.opacity(0.3) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ApplicationSourceRow: View {
    let source: SourceSelector.ApplicationSource
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // App icon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 36, height: 36)

                    Image(systemName: "app.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }

                // App info
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(source.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.green.opacity(0.3) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

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

        // Only check permissions strictly for Window/App tabs or if we want to be proactive.
        // For Display tab, we can use NSScreen which doesn't require permission to LIST (though it does to CAPTURE).
        // Allowing the list to load confirms the app is working.
        
        do {
            switch tab {
            case .display:
                // NSScreen based - should always work
                displaySources = try await sourceSelector.listDisplays()
                
                // Optional: Check permission in background to warn user, but don't block list
                let status = await permissionManager.checkScreenRecordingPermission()
                if status != .authorized {
                    print("⚠️ Screen recording permission missing, capture will fail")
                    // We could show a warning banner instead of full block
                }
                
            case .window:
                // SCShareableContent based - will throw if denied
                windowSources = try await sourceSelector.listWindows()
                
            case .application:
                // SCShareableContent based - will throw if denied
                applicationSources = try await sourceSelector.listApplications()
            }
        } catch {
            if let selectorError = error as? SourceSelector.SourceSelectorError,
               case .permissionDenied = selectorError {
                permissionDenied = true
                errorMessage = "Screen recording permission denied."
            } else {
                // Check for general SCStream errors that imply permission issues
                let nsError = error as NSError
                if nsError.domain.contains("SCStreamError") && nsError.code == -3801 {
                    permissionDenied = true
                    errorMessage = "Screen recording permission denied."
                } else {
                    errorMessage = "Failed to load sources: \(error.localizedDescription)"
                }
            }
            print("❌ Error loading sources: \(error)")
        }
    }
    
    func openSystemSettings() async {
        _ = await permissionManager.requestScreenRecordingPermission()
    }

    func capturePreview(display: SourceSelector.DisplaySource) async {
        // Show highlight on the actual display
        await MainActor.run {
            DisplayHighlighter.shared.toggleHighlight(displayID: display.id)
        }
        
        // Use a generic system icon as fallback for the UI thumbnail
        self.previewImage = NSImage(systemSymbolName: "display", accessibilityDescription: "Display Preview")
    }

    func capturePreview(window: SourceSelector.WindowSource) async {
        // CGWindowListCreateImage is unavailable in recent macOS SDKs
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
        // If highlighting same display, stop it (toggle off)
        if currentDisplayID == displayID {
            stopHighlight()
            return
        }
        
        // Stop current
        stopHighlight()
        
        guard let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return String(id.uint32Value) == displayID
        }) else {
            print("Could not find screen for ID: \(displayID)")
            return
        }
        
        // Create new window with safer settings
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen  // Explicitly set screen
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar  // Use statusBar level instead of floating for better stability
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .stationary]
        window.isReleasedWhenClosed = false  // Prevent premature deallocation
        
        let view = NSBox(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.boxType = .custom
        view.isTransparent = true
        view.fillColor = .clear
        
        view.wantsLayer = true
        view.layer?.borderWidth = 20 // Thicker border for visibility
        view.layer?.borderColor = NSColor.red.cgColor
        
        window.contentView = view
        
        window.setFrame(screen.frame, display: true)
        // Order front without making key to avoid stealing focus/crash
        window.orderFrontRegardless()  // Use orderFrontRegardless for better reliability
        
        highlightWindow = window
        currentDisplayID = displayID
        
        // Auto-remove after 3 seconds
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
            // Safer cleanup: orderOut first, then close
            window.orderOut(nil)
            // Small delay before closing to prevent crashes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.close()
            }
            highlightWindow = nil
        }
        currentDisplayID = nil
    }
}
