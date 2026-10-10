//
//  TimelineElement.swift
//  App
//
//  One lane for everything that sits on top of the footage: overlays (shapes, text, images),
//  imported still images and blur regions. Each chip carries a badge for its kind and elements
//  that do not overlap in time share a line, so the lane only grows when things stack.
//  Subtitles, video and audio keep their own lanes.
//

import SwiftUI
import EngineKit

struct TimelineElement: Identifiable {
    enum Source {
        case overlay(Project.Overlay)
        case image(Project.MediaItem)
        case blur(BlurRegion)
    }

    let source: Source

    var id: String {
        switch source {
        case .overlay(let o): return "overlay/\(o.id)"
        case .image(let m): return "image/\(m.id)"
        case .blur(let r): return "blur/\(r.id)"
        }
    }

    var start: TimeInterval {
        switch source {
        case .overlay(let o): return o.start
        case .image(let m): return m.timelineIn
        case .blur(let r): return r.absoluteStart
        }
    }

    var end: TimeInterval {
        switch source {
        case .overlay(let o): return o.end
        case .image(let m): return m.timelineOut
        case .blur(let r): return r.absoluteEnd
        }
    }

    var overlayId: UUID? {
        if case .overlay(let o) = source { return o.id }
        return nil
    }

    var icon: String {
        switch source {
        case .overlay(let o): return OverlayDisplayInfo.icon(for: o.type)
        case .image: return "photo"
        case .blur: return "drop.halffull"
        }
    }

    var label: String {
        switch source {
        case .overlay(let o): return OverlayDisplayInfo.label(for: o.type)
        case .image(let m): return m.name
        case .blur: return "Blur"
        }
    }

    var color: Color {
        switch source {
        case .overlay: return .cyan
        case .image: return .yellow
        case .blur: return .purple
        }
    }

    static func all(in project: Project) -> [TimelineElement] {
        let overlays = project.overlays.map { TimelineElement(source: .overlay($0)) }
        let images = project.mediaItems.filter { $0.type == .image }.map { TimelineElement(source: .image($0)) }
        let blurs = project.blurRegions.map { TimelineElement(source: .blur($0)) }
        return overlays + images + blurs
    }

    /// Greedy line packing by start time: an element goes on the first line where it does not overlap.
    /// Lines are keyed by their first element so a line keeps its view state when others move.
    static func pack(_ elements: [TimelineElement]) -> [ElementLine] {
        var lines: [[TimelineElement]] = []
        for element in elements.sorted(by: { $0.start < $1.start }) {
            if let index = lines.firstIndex(where: { line in !line.contains { element.start < $0.end && element.end > $0.start } }) {
                lines[index].append(element)
            } else {
                lines.append([element])
            }
        }
        return lines.map { ElementLine(id: $0[0].id, elements: $0) }
    }
}

struct ElementLine: Identifiable {
    let id: String
    let elements: [TimelineElement]
}

/// One line of the elements lane.
struct TimelineElementsRow: View {
    @ObservedObject var editor: ProjectEditor
    let elements: [TimelineElement]
    let layout: TimelineLayout
    let height: TimelineScalar
    @Binding var selectedOverlayId: UUID?
    @Binding var selectedMediaItemId: UUID?
    let onSeek: (TimeInterval) -> Void

    @State private var dragOffset: [String: TimelineScalar] = [:]
    @State private var popoverOverlayId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: layout.labelWidth)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                ForEach(elements) { element in
                    chip(element)
                }
            }
        }
    }

    private func isSelected(_ element: TimelineElement) -> Bool {
        switch element.source {
        case .overlay(let o): return o.id == selectedOverlayId
        case .image(let m): return m.id == selectedMediaItemId
        case .blur(let r): return r.id == editor.selectedBlurRegionId
        }
    }

    @ViewBuilder
    private func chip(_ element: TimelineElement) -> some View {
        let selected = isSelected(element)
        let width = layout.segmentWidth(for: element.end - element.start)
        HStack(spacing: 2) {
            Image(systemName: element.icon).font(.system(size: 8))
            Text(element.label).font(.system(size: 8)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .frame(width: max(width, 30), height: height - 10, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(element.color.opacity(selected ? 1.0 : 0.75)))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.white.opacity(selected ? 0.9 : 0.3), lineWidth: selected ? 2 : 1))
        .offset(x: layout.xPosition(for: element.start) - layout.labelWidth + (dragOffset[element.id] ?? 0))
        .popover(isPresented: Binding(
            get: { element.overlayId != nil && popoverOverlayId == element.overlayId },
            set: { if !$0 { popoverOverlayId = nil } }
        ), arrowEdge: .top) {
            if let id = element.overlayId { OverlayPopoverContent(editor: editor, overlayId: id) }
        }
        // highPriority so the chip wins over the timeline's seek gesture
        .highPriorityGesture(TapGesture().onEnded { select(element) })
        .highPriorityGesture(DragGesture(minimumDistance: 4)
            .onChanged { dragOffset[element.id] = $0.translation.width }
            .onEnded { value in
                dragOffset.removeValue(forKey: element.id)
                move(element, by: TimeInterval(value.translation.width / layout.pixelsPerSecond))
            })
        .help("\(element.label): click to select, drag to move in time")
    }

    private func select(_ element: TimelineElement) {
        // One element is selected at a time, whatever its kind.
        selectedOverlayId = nil
        selectedMediaItemId = nil
        editor.selectedBlurRegionId = nil
        popoverOverlayId = nil
        var seekTarget = element.start
        switch element.source {
        case .overlay(let o):
            selectedOverlayId = o.id
            popoverOverlayId = o.id
            seekTarget = OverlayFactory.revealTime(for: o)
        case .image(let m):
            selectedMediaItemId = m.id
        case .blur(let r):
            editor.selectedBlurRegionId = r.id
        }
        onSeek(seekTarget)
    }

    private func move(_ element: TimelineElement, by delta: TimeInterval) {
        switch element.source {
        case .overlay(let o):
            let start = max(0, o.start + delta)
            Task { _ = await editor.updateOverlay(projectId: editor.project.projectId, overlayId: o.id, start: start, end: start + (o.end - o.start)) }
        case .image(let m):
            Task { _ = await editor.updateMediaItem(id: m.id, timelineIn: max(0, m.timelineIn + delta)) }
        case .blur(let r):
            editor.selectedBlurRegionId = r.id
            let updated = r.shifted(by: delta)
            Task { _ = await editor.updateAdjustment(updated, inClipId: r.clip.id, trackId: r.trackId) }
        }
    }
}
