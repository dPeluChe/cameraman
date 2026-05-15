//
//  OverlayPositionCanvas.swift
//  App
//
//  Mini canvas used inside the overlay popover for visual position editing.
//  Extracted from OverlayPopover.swift to keep that file under the 400-500
//  LOC house rule.
//

import SwiftUI
import EngineKit

// MARK: - Position presets used by the popover's Position grid

enum PositionPreset: CaseIterable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    var x: Double {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft: return 0.15
        case .topCenter, .center, .bottomCenter: return 0.5
        case .topRight, .centerRight, .bottomRight: return 0.85
        }
    }

    var y: Double {
        switch self {
        case .topLeft, .topCenter, .topRight: return 0.15
        case .centerLeft, .center, .centerRight: return 0.5
        case .bottomLeft, .bottomCenter, .bottomRight: return 0.85
        }
    }

    var icon: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .topCenter: return "arrow.up"
        case .topRight: return "arrow.up.right"
        case .centerLeft: return "arrow.left"
        case .center: return "circle.fill"
        case .centerRight: return "arrow.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomCenter: return "arrow.down"
        case .bottomRight: return "arrow.down.right"
        }
    }

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .centerLeft: return "Center Left"
        case .center: return "Center"
        case .centerRight: return "Center Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}

// MARK: - Mini Position Canvas

struct OverlayPositionCanvas: View {
    let overlay: Project.Overlay
    let onPositionChange: (Double, Double) -> Void

    @State private var isDragging = false
    @State private var dragX: Double?
    @State private var dragY: Double?

    private var displayX: Double { dragX ?? overlay.transform.x }
    private var displayY: Double { dragY ?? overlay.transform.y }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let dotSize: CGFloat = 16
            let dotX = displayX * (size.width - dotSize) + dotSize / 2
            let dotY = displayY * (size.height - dotSize) + dotSize / 2

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                // Grid lines (thirds)
                Path { path in
                    for i in 1...2 {
                        let xPos = size.width * CGFloat(i) / 3
                        path.move(to: CGPoint(x: xPos, y: 0))
                        path.addLine(to: CGPoint(x: xPos, y: size.height))
                        let yPos = size.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: 0, y: yPos))
                        path.addLine(to: CGPoint(x: size.width, y: yPos))
                    }
                }
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)

                // Draggable dot — updates local state during drag, commits on end
                Circle()
                    .fill(isDragging ? Color.accentColor : Color.cyan)
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .position(x: dotX, y: dotY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                dragX = max(0, min(1, Double((value.location.x - dotSize / 2) / (size.width - dotSize))))
                                dragY = max(0, min(1, Double((value.location.y - dotSize / 2) / (size.height - dotSize))))
                            }
                            .onEnded { _ in
                                if let x = dragX, let y = dragY {
                                    onPositionChange(x, y)
                                }
                                isDragging = false
                                dragX = nil
                                dragY = nil
                            }
                    )

                Text(String(format: "%.0f%%, %.0f%%", displayX * 100, displayY * 100))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .position(x: size.width / 2, y: size.height - 8)
            }
        }
        .frame(height: 100)
    }
}
