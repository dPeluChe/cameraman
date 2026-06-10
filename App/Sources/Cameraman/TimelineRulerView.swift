//
//  TimelineRulerView.swift
//  App
//
//  Time ruler above the timeline tracks: adaptive ticks (1s…10min) with
//  mm:ss labels. Click or drag to move the playhead.
//

import SwiftUI

struct TimelineRulerView: View {
    let layout: TimelineLayout
    let onSeek: (TimeInterval) -> Void

    static let rulerHeight: TimelineScalar = 18

    var body: some View {
        Canvas { context, size in
            let pps = max(layout.pixelsPerSecond, 0.001)
            let majorInterval = Self.niceInterval(forPixelsPerSecond: pps)
            let minorInterval = majorInterval / 5

            // Minor ticks
            var time: TimeInterval = 0
            while time <= layout.duration {
                let x = layout.xPosition(for: time)
                let isMajor = time.truncatingRemainder(dividingBy: majorInterval) < 0.001
                let tickHeight: CGFloat = isMajor ? 7 : 4
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                context.stroke(path, with: .color(.secondary.opacity(isMajor ? 0.8 : 0.4)), lineWidth: 1)

                if isMajor {
                    context.draw(
                        Text(Self.label(for: time))
                            .font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary),
                        at: CGPoint(x: x + 3, y: 4),
                        anchor: .leading
                    )
                }
                time += minorInterval
            }
        }
        .frame(width: layout.contentWidth, height: Self.rulerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in onSeek(layout.time(forXPosition: value.location.x)) }
        )
        .help("Click or drag to move the playhead")
    }

    /// Pick a tick interval that keeps major labels ~70pt apart at this zoom.
    static func niceInterval(forPixelsPerSecond pps: TimelineScalar) -> TimeInterval {
        let targetSeconds = TimeInterval(70 / pps)
        let candidates: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return candidates.first { $0 >= targetSeconds } ?? 600
    }

    static func label(for time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
