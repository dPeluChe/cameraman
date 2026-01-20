//
//  AnimationEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// AnimationEngine provides animation calculations for overlays
/// Supports fade in/out, draw-on animations with various easing functions
public actor AnimationEngine {

    /// Initialize a new AnimationEngine
    public init() {}

    // MARK: - Animation Calculation

    /// Calculate the animation progress for an overlay at a given time
    /// - Parameters:
    ///   - overlay: The overlay with animation configuration
    ///   - time: Current playback time in seconds
    /// - Returns: Animation progress (0.0 to 1.0) and opacity
    public func calculateAnimationProgress(
        overlay: Project.Overlay,
        at time: TimeInterval
    ) -> (progress: Double, opacity: Double) {
        guard time >= overlay.start && time <= overlay.end else {
            return (0.0, 0.0)
        }

        guard let animation = overlay.animation else {
            // No animation - fully visible within the overlay range
            return (1.0, 1.0)
        }

        let duration = overlay.end - overlay.start
        let localTime = time - overlay.start

        switch animation.type {
        case .none:
            return (1.0, 1.0)

        case .fadeIn:
            return calculateFadeIn(
                localTime: localTime,
                duration: animation.fadeInDuration,
                easing: animation.easing
            )

        case .fadeOut:
            return calculateFadeOut(
                localTime: localTime,
                totalDuration: duration,
                fadeOutDuration: animation.fadeOutDuration,
                easing: animation.easing
            )

        case .fadeInOut:
            return calculateFadeInOut(
                localTime: localTime,
                totalDuration: duration,
                fadeInDuration: animation.fadeInDuration,
                fadeOutDuration: animation.fadeOutDuration,
                easing: animation.easing
            )

        case .drawOn:
            return calculateDrawOn(
                localTime: localTime,
                drawOnDuration: animation.drawOnDuration ?? duration * 0.5,
                easing: animation.easing
            )
        }
    }

    /// Calculate the current opacity for an overlay at a given time
    /// - Parameters:
    ///   - overlay: The overlay with animation configuration
    ///   - time: Current playback time in seconds
    /// - Returns: Opacity value (0.0 to 1.0)
    public func calculateOpacity(
        overlay: Project.Overlay,
        at time: TimeInterval
    ) -> Double {
        let (_, opacity) = calculateAnimationProgress(overlay: overlay, at: time)
        return opacity
    }

    /// Calculate the draw-on progress for line/shape overlays
    /// - Parameters:
    ///   - overlay: The overlay with animation configuration
    ///   - time: Current playback time in seconds
    /// - Returns: Progress value (0.0 to 1.0) indicating how much of the shape to draw
    public func calculateDrawOnProgress(
        overlay: Project.Overlay,
        at time: TimeInterval
    ) -> Double {
        let (progress, _) = calculateAnimationProgress(overlay: overlay, at: time)

        // For draw-on animations, progress indicates how much to draw
        if overlay.animation?.type == .drawOn {
            return progress
        }

        // For non-draw-on animations, return full progress
        return progress > 0 ? 1.0 : 0.0
    }

    // MARK: - Fade Calculations

    /// Calculate fade-in animation
    private func calculateFadeIn(
        localTime: TimeInterval,
        duration: TimeInterval,
        easing: Project.Overlay.Animation.EasingFunction
    ) -> (progress: Double, opacity: Double) {
        if localTime >= duration {
            return (1.0, 1.0)
        }

        let t = localTime / duration
        let easedT = applyEasing(t, easing: easing)

        return (easedT, easedT)
    }

    /// Calculate fade-out animation
    private func calculateFadeOut(
        localTime: TimeInterval,
        totalDuration: TimeInterval,
        fadeOutDuration: TimeInterval,
        easing: Project.Overlay.Animation.EasingFunction
    ) -> (progress: Double, opacity: Double) {
        let fadeOutStart = totalDuration - fadeOutDuration

        if localTime < fadeOutStart {
            return (1.0, 1.0)
        }

        let t = (localTime - fadeOutStart) / fadeOutDuration
        let easedT = 1.0 - applyEasing(t, easing: easing)

        return (easedT, easedT)
    }

    /// Calculate fade-in/out animation
    private func calculateFadeInOut(
        localTime: TimeInterval,
        totalDuration: TimeInterval,
        fadeInDuration: TimeInterval,
        fadeOutDuration: TimeInterval,
        easing: Project.Overlay.Animation.EasingFunction
    ) -> (progress: Double, opacity: Double) {
        let fadeOutStart = totalDuration - fadeOutDuration

        if localTime < fadeInDuration {
            // Fading in
            let t = localTime / fadeInDuration
            let easedT = applyEasing(t, easing: easing)
            return (easedT, easedT)
        } else if localTime >= fadeOutStart {
            // Fading out
            let t = (localTime - fadeOutStart) / fadeOutDuration
            let easedT = 1.0 - applyEasing(t, easing: easing)
            return (easedT, easedT)
        } else {
            // Fully visible
            return (1.0, 1.0)
        }
    }

    /// Calculate draw-on animation
    private func calculateDrawOn(
        localTime: TimeInterval,
        drawOnDuration: TimeInterval,
        easing: Project.Overlay.Animation.EasingFunction
    ) -> (progress: Double, opacity: Double) {
        if localTime >= drawOnDuration {
            return (1.0, 1.0)
        }

        let t = localTime / drawOnDuration
        let easedT = applyEasing(t, easing: easing)

        return (easedT, 1.0) // Full opacity, partial draw progress
    }

    // MARK: - Easing Functions

    /// Apply easing function to a normalized time value (0.0 to 1.0)
    /// - Parameters:
    ///   - t: Normalized time value (0.0 to 1.0)
    ///   - easing: Easing function to apply
    /// - Returns: Eased time value
    private func applyEasing(
        _ t: Double,
        easing: Project.Overlay.Animation.EasingFunction
    ) -> Double {
        guard t >= 0 && t <= 1.0 else {
            return t
        }

        switch easing {
        case .linear:
            return t

        case .easeIn:
            return t * t

        case .easeOut:
            return t * (2.0 - t)

        case .easeInOut:
            return t < 0.5
                ? 2.0 * t * t
                : 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
        }
    }

    // MARK: - Utility Methods

    /// Check if an overlay should be visible at a given time
    /// - Parameters:
    ///   - overlay: The overlay to check
    ///   - time: Current playback time
    /// - Returns: True if the overlay should be visible
    public func isVisible(
        overlay: Project.Overlay,
        at time: TimeInterval
    ) -> Bool {
        // Check time range
        guard time >= overlay.start && time <= overlay.end else {
            return false
        }

        // Check animation opacity
        let opacity = calculateOpacity(overlay: overlay, at: time)
        return opacity > 0.01 // Slight threshold for floating point precision
    }

    /// Get the effective render bounds for an overlay at a given time
    /// - Parameters:
    ///   - overlay: The overlay
    ///   - time: Current playback time
    /// - Returns: Effective opacity and draw progress
    public func getRenderState(
        overlay: Project.Overlay,
        at time: TimeInterval
    ) -> RenderState {
        let (progress, opacity) = calculateAnimationProgress(overlay: overlay, at: time)

        return RenderState(
            opacity: opacity,
            drawProgress: overlay.animation?.type == .drawOn ? progress : 1.0,
            isVisible: opacity > 0.01
        )
    }

    /// Render state for an overlay at a specific time
    public struct RenderState: Sendable {
        /// Current opacity (0.0 to 1.0)
        public let opacity: Double
        /// Draw progress for draw-on animations (0.0 to 1.0)
        public let drawProgress: Double
        /// Whether the overlay is visible
        public let isVisible: Bool

        public init(opacity: Double, drawProgress: Double, isVisible: Bool) {
            self.opacity = opacity
            self.drawProgress = drawProgress
            self.isVisible = isVisible
        }
    }
}
