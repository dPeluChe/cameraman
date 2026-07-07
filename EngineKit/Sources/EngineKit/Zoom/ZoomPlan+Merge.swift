//
//  ZoomPlan+Merge.swift
//  EngineKit
//
//  Merges auto-generated zoom keyframes with user-created manual keyframes.
//  Manual keyframes take precedence within overlapping auto-zoom events.
//

import Foundation

extension ZoomPlanGenerator.ZoomPlan {
    /// Merge this auto-generated plan with manual keyframes from the user.
    ///
    /// Rules:
    /// - All keyframes (auto + manual) are sorted by timestamp.
    /// - Manual keyframes override auto keyframes at the same timestamp.
    /// - The resulting plan uses the combined keyframe list for interpolation;
    ///   `zoomLevel(at:)` and `focusPoint(at:)` already work on any sorted list.
    /// - Auto events whose range fully contains a manual keyframe are split
    ///   so the manual keyframe's zoom level is respected during interpolation.
    ///
    /// - Parameter manualKeyframes: User-created keyframes (isManual == true).
    /// - Returns: A new plan with merged keyframes.
    public func merged(
        with manualKeyframes: [ZoomPlanGenerator.ZoomKeyframe]
    ) -> ZoomPlanGenerator.ZoomPlan {
        guard !manualKeyframes.isEmpty else { return self }
        guard !keyframes.isEmpty else {
            return ZoomPlanGenerator.ZoomPlan(
                events: [],
                keyframes: manualKeyframes.sorted { $0.timestamp < $1.timestamp },
                configuration: configuration,
                stats: stats
            )
        }

        let auto = keyframes.filter { !$0.isManual }
        let manual = manualKeyframes.sorted { $0.timestamp < $1.timestamp }

        // Merge: insert manual keyframes, and for each manual keyframe that
        // falls between two auto keyframes, insert an auto "echo" keyframe
        // just before and after so the transition is smooth.
        var combined: [ZoomPlanGenerator.ZoomKeyframe] = []
        combined.reserveCapacity(auto.count + manual.count + manual.count * 2)

        var autoIdx = 0
        for mk in manual {
            // Add all auto keyframes before this manual keyframe
            while autoIdx < auto.count && auto[autoIdx].timestamp < mk.timestamp {
                combined.append(auto[autoIdx])
                autoIdx += 1
            }
            // If there's a preceding auto keyframe, add an echo at the manual
            // timestamp with the interpolated auto value so the manual keyframe
            // creates a clean break point.
            if autoIdx > 0 && autoIdx < auto.count {
                let prev = auto[autoIdx - 1]
                let next = auto[autoIdx]
                let duration = next.timestamp - prev.timestamp
                if duration > 0 {
                    let progress = (mk.timestamp - prev.timestamp) / duration
                    let easedProgress = prev.easing.apply(to: progress)
                    let autoZoom = prev.zoomLevel + (next.zoomLevel - prev.zoomLevel) * easedProgress
                    let autoFX = prev.focusX + (next.focusX - prev.focusX) * easedProgress
                    let autoFY = prev.focusY + (next.focusY - prev.focusY) * easedProgress
                    combined.append(ZoomPlanGenerator.ZoomKeyframe(
                        id: UUID(),
                        timestamp: mk.timestamp - 0.001,
                        zoomLevel: autoZoom,
                        focusX: autoFX,
                        focusY: autoFY,
                        easing: .linear,
                        isManual: false
                    ))
                }
            }
            combined.append(mk)
        }
        // Add remaining auto keyframes
        while autoIdx < auto.count {
            combined.append(auto[autoIdx])
            autoIdx += 1
        }

        let sorted = combined.sorted { $0.timestamp < $1.timestamp }

        return ZoomPlanGenerator.ZoomPlan(
            events: events,
            keyframes: sorted,
            configuration: configuration,
            stats: stats
        )
    }

    /// Convenience: merge with manual keyframes stored on a project.
    public func merged(withProject project: Project) -> ZoomPlanGenerator.ZoomPlan {
        guard let manual = project.manualZoomKeyframes, !manual.isEmpty else { return self }
        return merged(with: manual)
    }
}
