//
//  PreviewPlayerViewModel+Plans.swift
//  App
//
//  Zoom/cursor plan computation, live draft pushes (overlay/camera drag),
//  and audio mix application. Extracted from PreviewPlayerViewModel.swift to
//  keep it inside the 400-500 line budget. `applyEffectiveZoomPlan` stays in
//  the main file because it replaces the private(set) `project`.
//

import AVFoundation
import EngineKit
import Foundation

extension PreviewPlayerViewModel {
    /// Store the unfiltered plan, then push the effective plan to the engine.
    /// Defers if the engine is still loading.
    func setZoomPlan(_ plan: ZoomPlanGenerator.ZoomPlan?) {
        originalZoomPlan = plan
        applyEffectiveZoomPlan()
    }

    /// Store the unfiltered cursor plan, then push the effective plan to the engine.
    func setCursorPlan(_ plan: CursorPlan?) {
        originalCursorPlan = plan
        applyEffectiveCursorPlan()
    }

    /// Recompute the effective cursor plan: nil when the feature is disabled or
    /// no original plan exists; push it to the engine.
    func applyEffectiveCursorPlan() {
        let effective = computeEffectiveCursorPlan()
        guard let engine = previewEngine else { return }
        Task { await engine.setCursorPlan(effective) }
    }

    /// Build the plan that should currently apply: nil when zoom is hidden, when
    /// no original plan exists, or when filtering wipes every event. Merges
    /// manual keyframes from the project before filtering.
    func computeEffectiveZoomPlan() -> ZoomPlanGenerator.ZoomPlan? {
        guard showZoom, let plan = originalZoomPlan else {
            if showZoom, let manual = project?.manualZoomKeyframes, !manual.isEmpty {
                let manualPlan = ZoomPlanGenerator.manualOnlyPlan(from: manual)
                let segments = project?.timeline.segments ?? []
                let filtered = manualPlan.filtered(byEnabledSegments: segments)
                return filtered.hasNoZoom ? nil : filtered
            }
            return nil
        }
        let merged = plan.merged(with: project?.manualZoomKeyframes ?? [])
        let segments = project?.timeline.segments ?? []
        let filtered = merged.filtered(byEnabledSegments: segments)
        return filtered.hasNoZoom ? nil : filtered
    }

    /// Build the cursor plan that should currently apply: nil when the project
    /// has the feature disabled or no original plan exists.
    func computeEffectiveCursorPlan() -> CursorPlan? {
        guard project?.syntheticCursor?.enabled == true, let plan = originalCursorPlan else { return nil }
        return plan
    }

    /// Push an overlay-transform draft directly to the engine, bypassing
    /// `editor.project` publication + the 150ms debounce in PreviewPlayerView.
    /// Used by OverlayInteractionLayer during an active drag. Official
    /// editor.updateOverlay still fires on gesture end.
    func previewOverlayDraft(_ transform: Project.Overlay.Transform, overlayId: UUID) {
        guard let baseProject = project, let engine = previewEngine else { return }
        var temp = baseProject
        guard let idx = temp.overlays.firstIndex(where: { $0.id == overlayId }) else { return }
        temp.overlays[idx].transform = transform
        Task { try? await engine.updateProject(temp) }
    }

    /// Push a camera-position-only draft directly to the engine, bypassing
    /// `editor.project` publication + the 150ms debounce in PreviewPlayerView.
    /// Used by PiPCanvasEditor during an active drag so the live AVPlayer
    /// reflects the in-progress position. The official editor.project update
    /// happens on gesture release (via the existing commitCamera path); this
    /// just keeps the visual in sync mid-drag.
    /// Hits `PreviewEngine.updateProject` light path (camera position alone
    /// doesn't change render size or clip count) → `currentItem.videoComposition`
    /// is swapped in-place, no AVPlayer recreation, no playback reset.
    func previewCameraDraft(_ camera: Project.Canvas.Layout.CameraPosition, segmentId: String?) {
        guard let baseProject = project, let engine = previewEngine else { return }
        var temp = baseProject
        if let segId = segmentId,
           let idx = temp.timeline.segments.firstIndex(where: { $0.id == segId }) {
            temp.timeline.segments[idx].cameraPosition = camera
        } else {
            temp.canvas.layout.camera = camera
        }
        Task { try? await engine.updateProject(temp) }
    }

    // MARK: - Audio Mix

    func applyTrackMutes(mutedTracks: Set<TimelineTrackKind>) {
        guard let engine = previewEngine else { return }

        let audioMuteState = AudioMixBuilder.TrackMuteState(
            systemAudioMuted: mutedTracks.contains(.systemAudio),
            micAudioMuted: mutedTracks.contains(.micAudio),
            systemAudioVolume: systemAudioVolume,
            micAudioVolume: micAudioVolume
        )
        let audioChanged = audioMuteState != lastMuteState
        if audioChanged { lastMuteState = audioMuteState }

        let screenMuted = mutedTracks.contains(.screen)
        let cameraMuted = mutedTracks.contains(.camera)
        let subtitlesHidden = mutedTracks.contains(.subtitle)

        Task {
            if audioChanged {
                await engine.applyAudioMix(audioMuteState)
            }
            await engine.applyVideoMutes(screenMuted: screenMuted, cameraMuted: cameraMuted, subtitlesHidden: subtitlesHidden)
        }
    }

    func reapplyAudioMix() {
        guard let engine = previewEngine else { return }
        let audioMuteState = AudioMixBuilder.TrackMuteState(
            systemAudioMuted: lastMuteState?.systemAudioMuted ?? false,
            micAudioMuted: lastMuteState?.micAudioMuted ?? false,
            systemAudioVolume: systemAudioVolume,
            micAudioVolume: micAudioVolume
        )
        guard audioMuteState != lastMuteState else { return }
        lastMuteState = audioMuteState
        Task { await engine.applyAudioMix(audioMuteState) }
    }
}
