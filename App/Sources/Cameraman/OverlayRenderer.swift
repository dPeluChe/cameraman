//
//  OverlayRenderer.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

extension OverlayEditorView {
    // MARK: - Overlay Rendering

    @ViewBuilder
    func renderOverlay(_ overlay: Project.Overlay, in size: CGSize) -> some View {
        let rect = overlayRect(overlay, in: size)

        switch overlay.type {
        case .arrow:
            renderArrow(overlay, in: rect)
        case .rect:
            renderRectangle(overlay, in: rect)
        case .line:
            renderLine(overlay, in: rect)
        case .text:
            renderText(overlay, in: rect)
        case .image:
            renderImage(overlay, in: rect)
        }
    }

    @ViewBuilder
    func renderImage(_ overlay: Project.Overlay, in rect: CGRect) -> some View {
        if let path = overlay.style.imagePath,
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .opacity(overlay.style.imageOpacity ?? 1.0)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        } else {
            // Missing asset — show a placeholder so the user sees something is broken
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: min(rect.width, rect.height) * 0.5))
                .foregroundStyle(.secondary)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    func renderArrow(_ overlay: Project.Overlay, in rect: CGRect) -> some View {
        let style = overlay.style

        return Path { path in
            let startPoint = CGPoint(x: rect.minX, y: rect.maxY)
            let endPoint = CGPoint(x: rect.maxX, y: rect.minY)

            // Line
            path.move(to: startPoint)
            path.addLine(to: endPoint)

            // Arrowhead
            let arrowSize: CGFloat = 12
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let arrowPoint1 = CGPoint(
                x: endPoint.x - arrowSize * cos(angle - .pi / 6),
                y: endPoint.y - arrowSize * sin(angle - .pi / 6)
            )
            let arrowPoint2 = CGPoint(
                x: endPoint.x - arrowSize * cos(angle + .pi / 6),
                y: endPoint.y - arrowSize * sin(angle + .pi / 6)
            )

            path.move(to: endPoint)
            path.addLine(to: arrowPoint1)
            path.move(to: endPoint)
            path.addLine(to: arrowPoint2)
        }
        .stroke(color(from: overlay.style.stroke), lineWidth: style.strokeWidth)
        .shadow(color: .black.opacity(0.33), radius: style.shadow ? 2 : 0)
    }

    func renderRectangle(_ overlay: Project.Overlay, in rect: CGRect) -> some View {
        let style = overlay.style

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(color(from: style.stroke), lineWidth: style.strokeWidth)
            .background(style.bg.map { color(from: $0).opacity(0.3) })
            .shadow(color: .black.opacity(0.33), radius: style.shadow ? 2 : 0)
    }

    func renderLine(_ overlay: Project.Overlay, in rect: CGRect) -> some View {
        let style = overlay.style

        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        .stroke(color(from: style.stroke), lineWidth: style.strokeWidth)
        .shadow(color: .black.opacity(0.33), radius: style.shadow ? 2 : 0)
    }

    func renderText(_ overlay: Project.Overlay, in rect: CGRect) -> some View {
        let style = overlay.style
        let fontName = style.font ?? "Helvetica"
        let fontSize = style.size ?? 24
        let textColor = style.color.map { color(from: $0) } ?? .primary

        return Text(style.text ?? "Text")
            .font(.custom(fontName, size: fontSize))
            .foregroundColor(textColor)
            .frame(width: rect.width, height: rect.height)
            .background(style.bg.map { color(from: $0).opacity(0.5) })
            .shadow(color: .black.opacity(0.33), radius: style.shadow ? 2 : 0)
    }

    // MARK: - Selection and Handles

    @ViewBuilder
    func selectionBorder(for overlay: Project.Overlay) -> some View {
        let rect = overlayRect(overlay, in: CGSize(width: 800, height: 300)) // Approximate

        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: rect.width + 8, height: rect.height + 8)
    }
}
