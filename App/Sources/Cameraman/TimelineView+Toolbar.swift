//
//  TimelineView+Toolbar.swift
//  App
//
//  Toolbar row (undo/redo/split/delete, zoom suggestions, import, view
//  toggles, zoom scale) and the segment inspector bar. Extracted from
//  TimelineView.swift to keep it inside the 400-500 line budget.
//

import SwiftUI
import EngineKit

extension TimelineView {
    // MARK: - Toolbar

    @ViewBuilder
    var timelineToolbar: some View {
        HStack(spacing: 12) {
            Text("Timeline")
                .font(.headline)

            Spacer()

            Button("Undo") { undoEdit() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!editor.canUndo)

            Button("Redo") { redoEdit() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!editor.canRedo)

            Button("Split") { splitAtPlayhead() }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!canSplitAtPlayhead)

            Button("Delete") { deleteSelectedSegment() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedSegmentId == nil)

            zoomSuggestionButtons
            importAndViewToggles
            zoomScaleControls
        }
    }

    @ViewBuilder
    private var zoomSuggestionButtons: some View {
        if !zoomSuggestions.isEmpty {
            Button {
                applyZoomSuggestions()
            } label: {
                Label("Apply (\(activeSuggestions.count)/\(zoomSuggestions.count))", systemImage: "checkmark.circle")
            }
            .disabled(activeSuggestions.isEmpty)
            .help("Apply selected zoom suggestions as keyframes")

            Button {
                zoomSuggestions = []
                dismissedSuggestionIds = []
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Dismiss all zoom suggestions")
        } else {
            Button {
                generateZoomSuggestions()
            } label: {
                Label("Suggest Zooms", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(isGeneratingSuggestions || !hasCursorTelemetry)
            .help(hasCursorTelemetry ? "Detect zoom points from cursor telemetry" : "No cursor telemetry available")
        }
    }

    @ViewBuilder
    private var importAndViewToggles: some View {
        Button {
            showImportPanel = true
        } label: {
            Label("Import", systemImage: "plus.circle")
        }
        .help("Import video, audio or image asset")

        Button {
            if showVoiceoverPanel {
                Task { await voiceoverVM.cancelRecording() }
                showVoiceoverPanel = false
            } else {
                voiceoverVM.editor = editor
                voiceoverVM.playerViewModel = playerViewModel
                voiceoverVM.projectDirectory = projectDirectory
                showVoiceoverPanel = true
            }
        } label: {
            Label("Voiceover", systemImage: "mic.circle")
        }
        .help("Record voiceover narration at playhead")

        Menu {
            Toggle("Thumbnails", isOn: $showThumbnails)
                .disabled(thumbnailCache == nil)
            Toggle("Waveforms", isOn: $showWaveforms)
                .disabled(thumbnailCache == nil || waveforms.isEmpty)
            Divider()
            Toggle("Zoom Plan", isOn: $playerViewModel.showZoom)
            Divider()
            Toggle("Cursor", isOn: $playerViewModel.showCursor)
            Toggle("Clicks", isOn: $playerViewModel.showClicks)
            Toggle("Keystrokes", isOn: $playerViewModel.showKeystrokes)
        } label: {
            Label("View", systemImage: "eye")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Timeline and preview visibility options")
    }

    @ViewBuilder
    private var zoomScaleControls: some View {
        Button {
            zoomScale = max(1, zoomScale / 2)
        } label: {
            Image(systemName: "minus.magnifyingglass")
        }
        .buttonStyle(.borderless)
        .disabled(zoomScale <= 1.001)
        .help("Zoom out (100% = whole timeline)")

        Button("Fit") {
            zoomScale = 1
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .disabled(zoomScale <= 1.001)
        .help("Fit the whole timeline in view")

        Text("\(Int(zoomScale * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)

        Button {
            zoomScale = zoomScale * 2
        } label: {
            Image(systemName: "plus.magnifyingglass")
        }
        .buttonStyle(.borderless)
        .disabled(!canZoomIn)
    }

    // MARK: - Segment Inspector

    @ViewBuilder
    var segmentInspector: some View {
        if let segId = selectedSegmentId,
           let segment = project.timeline.segments.first(where: { $0.id == segId }) {
            SegmentInspectorBar(
                segment: segment,
                projectCamera: project.canvas.layout.camera,
                onSpeedChange: { speed in
                    Task { await editor.updateSegmentSpeed(segmentId: segId, speed: speed) }
                },
                onCameraOverride: {
                    let camera = segment.cameraPosition ?? project.canvas.layout.camera
                    Task { await editor.updateSegmentCameraPosition(segmentId: segId, camera: camera) }
                },
                onCameraReset: {
                    Task { await editor.updateSegmentCameraPosition(segmentId: segId, camera: nil) }
                },
                onVolumeChange: { vol in
                    Task { await editor.updateSegmentVolume(segmentId: segId, volume: vol) }
                },
                onMuteToggle: { muted in
                    Task { await editor.updateSegmentAudioMuted(segmentId: segId, muted: muted) }
                }
            )
        }
    }
}
