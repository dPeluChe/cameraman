//
//  TimelineView+EditActions.swift
//  App
//
//  Extracted from TimelineView.swift (Phase 1 refactor, v0.5.1).
//  Split/delete/undo/redo actions, volume binding, overlay row packing.
//

import SwiftUI
import EngineKit

extension TimelineView {
    var canSplitAtPlayhead: Bool {
        TimelineEditingHelper.segmentForSplit(at: playerViewModel.currentTime, in: project.timeline.segments) != nil
    }

    func splitAtPlayhead() {
        let playheadTime = playerViewModel.currentTime
        guard let segment = TimelineEditingHelper.segmentForSplit(at: playheadTime, in: project.timeline.segments) else {
            return
        }

        Task {
            let result = await editor.split(segmentId: segment.id, at: playheadTime)
            if case .successWithInfo(_, .splitCreated(let newSegmentId)) = result {
                selectedSegmentId = newSegmentId
            }
        }
    }

    func deleteSelectedSegment() {
        guard let selectedSegmentId else { return }

        Task {
            _ = await editor.delete(segmentId: selectedSegmentId)
        }

        self.selectedSegmentId = nil
    }

    func undoEdit() {
        Task {
            let didUndo = await editor.undo()
            if didUndo {
                selectedSegmentId = nil
                selection = nil
                let clampedTime = min(playerViewModel.currentTime, editor.project.timeline.duration)
                playerViewModel.seek(to: clampedTime)
            }
        }
    }

    func redoEdit() {
        Task {
            let didRedo = await editor.redo()
            if didRedo {
                selectedSegmentId = nil
                selection = nil
                let clampedTime = min(playerViewModel.currentTime, editor.project.timeline.duration)
                playerViewModel.seek(to: clampedTime)
            }
        }
    }

    func volumeBinding(for kind: TimelineTrackKind) -> Binding<Float>? {
        switch kind {
        case .systemAudio: return $playerViewModel.systemAudioVolume
        case .micAudio: return $playerViewModel.micAudioVolume
        default: return nil
        }
    }

    /// Greedy algorithm to split overlays into non-overlapping rows.
    static func computeOverlayRows(overlays: [Project.Overlay]) -> [[Project.Overlay]] {
        var rows: [[Project.Overlay]] = []
        let sorted = overlays.sorted { $0.start < $1.start }

        for overlay in sorted {
            var placed = false
            for (i, row) in rows.enumerated() {
                let overlaps = row.contains { rowOverlay in
                    overlay.start < rowOverlay.end && overlay.end > rowOverlay.start
                }
                if !overlaps {
                    rows[i].append(overlay)
                    placed = true
                    break
                }
            }
            if !placed {
                rows.append([overlay])
            }
        }
        return rows
    }
}
