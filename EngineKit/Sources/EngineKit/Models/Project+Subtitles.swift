//
//  Project+Subtitles.swift
//  EngineKit
//
//  Subtitle (caption) model. Subtitles are stored as styled text overlays in
//  `Project.subtitles`, kept separate from annotation overlays so they can be
//  generated, restyled, and cleared as a group while still reusing the existing
//  text-overlay rendering pipeline (preview compositor + export burn-in).
//

import Foundation

extension Project {
    /// Global default styling for subtitles. Each subtitle cue is materialized as
    /// a text `Overlay`, so per-cue color/position changes are simply edits to that
    /// overlay; this struct is the template used when generating cues from a
    /// transcript and by the "apply style to all" action.
    public struct SubtitleStyle: Codable, Equatable {
        /// Typography color (hex, e.g. "#FFFFFF").
        public var textColor: String
        /// Font size in points, measured at a 1920px-wide canvas baseline.
        public var fontSize: Double
        /// Optional background box color (hex). `nil` means no background box.
        public var backgroundColor: String?
        /// Vertical position as a fraction from the bottom (0 = bottom, 1 = top).
        public var verticalPosition: Double
        /// Horizontal center as a fraction (0 = left, 0.5 = center, 1 = right).
        public var horizontalPosition: Double
        /// Drop shadow for legibility over busy footage.
        public var shadow: Bool
        /// Text box width as a fraction of the canvas width.
        public var width: Double

        public init(
            textColor: String = "#FFFFFF",
            fontSize: Double = 48,
            backgroundColor: String? = nil,
            verticalPosition: Double = 0.12,
            horizontalPosition: Double = 0.5,
            shadow: Bool = true,
            width: Double = 0.6
        ) {
            self.textColor = textColor
            self.fontSize = fontSize
            self.backgroundColor = backgroundColor
            self.verticalPosition = verticalPosition
            self.horizontalPosition = horizontalPosition
            self.shadow = shadow
            self.width = width
        }

        /// Default subtitle style: white, bottom-centered, shadowed, no background.
        public static let `default` = SubtitleStyle()
    }
}

extension Project.Overlay {
    /// Build a subtitle overlay (a styled text overlay) for a single timed cue.
    /// - Parameters:
    ///   - id: Stable identity (preserved across restyle so undo/selection hold).
    ///   - text: Cue text. Keep cues short — the text overlay renderer draws a
    ///     single centered line, so the generator splits long segments.
    ///   - start/end: Cue time window on the timeline (seconds).
    ///   - style: Template style to apply.
    public static func subtitle(
        id: UUID = UUID(),
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        style: Project.SubtitleStyle
    ) -> Project.Overlay {
        // The text overlay's base box is 0.35 of the canvas width (OverlayBaseSize);
        // scale it up/down to reach the requested subtitle width.
        let scale = max(0.1, style.width / 0.35)
        return Project.Overlay(
            id: id,
            type: .text,
            start: start,
            end: end,
            transform: Project.Overlay.Transform(
                x: style.horizontalPosition,
                y: style.verticalPosition,
                scale: scale,
                rotation: 0
            ),
            style: Project.Overlay.Style(
                stroke: style.textColor,
                strokeWidth: 0,
                shadow: style.shadow,
                font: nil,
                size: style.fontSize,
                color: style.textColor,
                bg: style.backgroundColor,
                text: text
            ),
            animation: Project.Overlay.Animation(
                type: .fadeInOut,
                fadeInDuration: 0.12,
                fadeOutDuration: 0.12
            )
        )
    }

    /// Re-derive this subtitle's transform/style from a new template, preserving
    /// the cue's text, timing, and identity.
    public func restyledAsSubtitle(with style: Project.SubtitleStyle) -> Project.Overlay {
        Project.Overlay.subtitle(
            id: id,
            text: self.style.text ?? "",
            start: start,
            end: end,
            style: style
        )
    }
}

extension Project.SubtitleStyle {
    /// Split a transcript segment into one or more subtitle cues so that each
    /// rendered line stays short enough to fit the configured width. Time is
    /// apportioned across the resulting cues by character count.
    /// - Parameter maxCharacters: Soft cap per cue (default ~42, standard for captions).
    public static func cues(
        forSegmentText text: String,
        start: TimeInterval,
        end: TimeInterval,
        maxCharacters: Int = 42
    ) -> [(text: String, start: TimeInterval, end: TimeInterval)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > maxCharacters else {
            return [(trimmed, start, end)]
        }

        // Greedy word wrap into chunks of up to maxCharacters.
        var chunks: [String] = []
        var current = ""
        for word in trimmed.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { chunks.append(current) }

        let totalChars = max(1, chunks.reduce(0) { $0 + $1.count })
        let totalDuration = max(0, end - start)
        var cues: [(text: String, start: TimeInterval, end: TimeInterval)] = []
        var cursor = start
        for (index, chunk) in chunks.enumerated() {
            let portion = totalDuration * Double(chunk.count) / Double(totalChars)
            let cueEnd = index == chunks.count - 1 ? end : cursor + portion
            cues.append((chunk, cursor, cueEnd))
            cursor = cueEnd
        }
        return cues
    }
}
