//
//  RecordingQuality.swift
//  EngineKit
//

import Foundation

/// Output quality preset for screen recording.
/// Scales the native display resolution down to fit within the preset bounds,
/// preserving aspect ratio. Never upscales.
public enum RecordingQuality: String, CaseIterable, Codable, Sendable {
    case native = "Native"
    case hd1080 = "1080p"
    case hd720 = "720p"

    /// Compute output pixel dimensions for the given native pixel dimensions.
    /// The result fits within the quality bounds while preserving aspect ratio.
    public func outputSize(nativeWidth: Int, nativeHeight: Int) -> (width: Int, height: Int) {
        switch self {
        case .native:
            return (nativeWidth, nativeHeight)
        case .hd1080:
            return scaled(nativeWidth, nativeHeight, maxWidth: 1920, maxHeight: 1080)
        case .hd720:
            return scaled(nativeWidth, nativeHeight, maxWidth: 1280, maxHeight: 720)
        }
    }

    private func scaled(_ w: Int, _ h: Int, maxWidth: Int, maxHeight: Int) -> (Int, Int) {
        let factor = min(1.0, min(Double(maxWidth) / Double(w), Double(maxHeight) / Double(h)))
        // Ensure dimensions are even (required by H.264 encoder)
        let outW = Int(Double(w) * factor) & ~1
        let outH = Int(Double(h) * factor) & ~1
        return (outW, outH)
    }
}
