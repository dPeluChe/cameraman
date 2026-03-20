//
//  OverlayEngineHelpers.swift
//  EngineKit
//
//  Extracted from OverlayEngine.swift — convenience factory methods
//

import Foundation

extension OverlayEngine {
    /// Create an arrow overlay
    public func addArrowOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 6.0,
        shadow: Bool = true,
        animation: Project.Overlay.Animation? = nil
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(stroke: stroke, strokeWidth: strokeWidth, shadow: shadow)

        return try await addOverlay(
            projectId: projectId,
            type: .arrow,
            start: start,
            end: end,
            transform: transform,
            style: style,
            animation: animation
        )
    }

    /// Create a rectangle overlay
    public func addRectOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 4.0,
        shadow: Bool = true,
        animation: Project.Overlay.Animation? = nil
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(stroke: stroke, strokeWidth: strokeWidth, shadow: shadow)

        return try await addOverlay(
            projectId: projectId,
            type: .rect,
            start: start,
            end: end,
            transform: transform,
            style: style,
            animation: animation
        )
    }

    /// Create a line overlay
    public func addLineOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 4.0,
        shadow: Bool = true,
        animation: Project.Overlay.Animation? = nil
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(stroke: stroke, strokeWidth: strokeWidth, shadow: shadow)

        return try await addOverlay(
            projectId: projectId,
            type: .line,
            start: start,
            end: end,
            transform: transform,
            style: style,
            animation: animation
        )
    }

    /// Create a text overlay
    public func addTextOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        text: String,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        font: String = "SF Pro",
        size: Double = 36.0,
        color: String = "#FFFFFF",
        bg: String? = "rgba(0,0,0,0.4)",
        animation: Project.Overlay.Animation? = nil
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(
            stroke: "",
            strokeWidth: 0,
            shadow: false,
            font: font,
            size: size,
            color: color,
            bg: bg,
            text: text
        )

        return try await addOverlay(
            projectId: projectId,
            type: .text,
            start: start,
            end: end,
            transform: transform,
            style: style,
            animation: animation
        )
    }

    /// Create an arrow overlay with draw-on animation
    public func addArrowOverlayWithDrawOn(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 6.0,
        shadow: Bool = true,
        drawOnDuration: TimeInterval = 0.5,
        easing: Project.Overlay.Animation.EasingFunction = .easeOut
    ) async throws -> OverlayResult {
        let animation = Project.Overlay.Animation.drawOn(duration: drawOnDuration)
        var mutableAnimation = animation
        mutableAnimation.easing = easing

        return try await addArrowOverlay(
            projectId: projectId,
            start: start,
            end: end,
            x: x,
            y: y,
            scale: scale,
            rotation: rotation,
            stroke: stroke,
            strokeWidth: strokeWidth,
            shadow: shadow,
            animation: mutableAnimation
        )
    }

    /// Create a line overlay with draw-on animation
    public func addLineOverlayWithDrawOn(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 4.0,
        shadow: Bool = true,
        drawOnDuration: TimeInterval = 0.5,
        easing: Project.Overlay.Animation.EasingFunction = .easeOut
    ) async throws -> OverlayResult {
        let animation = Project.Overlay.Animation.drawOn(duration: drawOnDuration)
        var mutableAnimation = animation
        mutableAnimation.easing = easing

        return try await addLineOverlay(
            projectId: projectId,
            start: start,
            end: end,
            x: x,
            y: y,
            scale: scale,
            rotation: rotation,
            stroke: stroke,
            strokeWidth: strokeWidth,
            shadow: shadow,
            animation: mutableAnimation
        )
    }

    /// Create a text overlay with fade-in animation
    public func addTextOverlayWithFadeIn(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        text: String,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        font: String = "SF Pro",
        size: Double = 36.0,
        color: String = "#FFFFFF",
        bg: String? = "rgba(0,0,0,0.4)",
        fadeInDuration: TimeInterval = 0.3,
        easing: Project.Overlay.Animation.EasingFunction = .easeOut
    ) async throws -> OverlayResult {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: fadeInDuration,
            fadeOutDuration: 0,
            easing: easing
        )

        return try await addTextOverlay(
            projectId: projectId,
            start: start,
            end: end,
            x: x,
            y: y,
            text: text,
            scale: scale,
            rotation: rotation,
            font: font,
            size: size,
            color: color,
            bg: bg,
            animation: animation
        )
    }

    /// Create any overlay with fade-in/out animation
    public func addOverlayWithFadeInOut(
        projectId: ProjectId,
        type: Project.Overlay.OverlayType,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        style: Project.Overlay.Style,
        fadeInDuration: TimeInterval = 0.3,
        fadeOutDuration: TimeInterval = 0.3,
        easing: Project.Overlay.Animation.EasingFunction = .easeInOut
    ) async throws -> OverlayResult {
        let animation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: fadeInDuration,
            fadeOutDuration: fadeOutDuration,
            easing: easing
        )

        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)

        return try await addOverlay(
            projectId: projectId,
            type: type,
            start: start,
            end: end,
            transform: transform,
            style: style,
            animation: animation
        )
    }
}
