//
//  LiveAnnotation.swift
//  EngineKit
//
//  Shapes the presenter draws over the screen while recording. The log keeps what was visible
//  and when, so the same data can drive the on-screen canvas and, later, project overlays.
//

import Foundation
import CoreGraphics

public struct LiveAnnotation: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case arrow, rect, ellipse, pen, text, blur
    }

    public var id: UUID
    public var kind: Kind
    /// Normalized display coordinates, top-left origin. arrow: [tail, head]; rect/ellipse/blur:
    /// [corner, opposite corner]; text: [anchor]; pen: the stroke.
    public var points: [CGPoint]
    public var colorHex: String
    public var lineWidth: Double
    public var text: String?
    /// Seconds since the recording started.
    public var start: TimeInterval
    /// nil while it is still on screen.
    public var end: TimeInterval?

    public init(
        id: UUID = UUID(), kind: Kind, points: [CGPoint], colorHex: String, lineWidth: Double,
        text: String? = nil, start: TimeInterval, end: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.text = text
        self.start = start
        self.end = end
    }

    /// Bounding box of `points` (rect, ellipse and blur are defined by two corners).
    public var bounds: CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// A shape too small to see (a click without a drag) is dropped instead of recorded.
    public var isDegenerate: Bool {
        switch kind {
        case .text: return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .pen: return points.count < 2
        default:
            let b = bounds
            return max(b.width, b.height) < Self.minExtent
        }
    }

    /// Text size in points for a text annotation drawn with this stroke width.
    public var textPointSize: Double { Self.textPointSize(forLineWidth: lineWidth) }
    public static func textPointSize(forLineWidth width: Double) -> Double { 14 + width * 5 }

    /// Ends the shape at `time`, never before it started.
    public mutating func end(at time: TimeInterval) { end = max(time, start) }

    static let minExtent = 0.004
}

/// What was on screen over time. Undo and clear end shapes instead of deleting them, so the log
/// stays a faithful record of the recording.
public struct LiveAnnotationLog: Codable, Equatable, Sendable {
    public private(set) var items: [LiveAnnotation] = []

    public init() {}

    public var visible: [LiveAnnotation] { items.filter { $0.end == nil } }
    public var isEmpty: Bool { items.isEmpty }

    /// Adds a finished shape; returns false for one too small or empty to matter.
    @discardableResult
    public mutating func add(_ annotation: LiveAnnotation) -> Bool {
        guard !annotation.isDegenerate else { return false }
        items.append(annotation)
        return true
    }

    /// Removes the most recent visible shape, as of `time`.
    @discardableResult
    public mutating func undo(at time: TimeInterval) -> Bool {
        guard let index = items.lastIndex(where: { $0.end == nil }) else { return false }
        items[index].end(at: time)
        return true
    }

    public mutating func clear(at time: TimeInterval) {
        for index in items.indices where items[index].end == nil { items[index].end(at: time) }
    }
}
