//
//  ExportTypes.swift
//  EngineKit
//
//  Extracted from ExportEngine.swift
//

import Foundation
import AppKit

// MARK: - Export Errors

/// Export engine errors
public enum ExportError: Error, LocalizedError, Equatable, Sendable {
    case noSegments
    case missingSourceFile(String)
    case sourceFileNotFound(String)
    case mediaFileNotFound(String)
    case assetNotReadable(String)
    case compositionFailed(String)
    case noVideoTrack
    case exportSessionCreationFailed
    case exportFailed(String)
    case outputFileEmpty
    case insufficientDiskSpace
    case audioSyncDrift(TimeInterval)

    public var localizedDescription: String {
        switch self {
        case .noSegments:
            return "Project has no timeline segments to export"
        case .missingSourceFile(let message):
            return "Missing source file: \(message)"
        case .sourceFileNotFound(let path):
            return "Source file not found: \(path)"
        case .mediaFileNotFound(let path):
            return "Media file not found: \(path)"
        case .assetNotReadable(let asset):
            return "Asset not readable: \(asset)"
        case .compositionFailed(let reason):
            return "Failed to create composition: \(reason)"
        case .noVideoTrack:
            return "No video track found in source asset"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .outputFileEmpty:
            return "Output file is empty or was not created"
        case .insufficientDiskSpace:
            return "Insufficient disk space for export"
        case .audioSyncDrift(let drift):
            return "Audio sync drift detected: \(drift * 1000)ms"
        }
    }

    // LocalizedError: without this, `error.localizedDescription` (used when an
    // export job fails) falls back to the opaque "ExportError error N" NSError text.
    public var errorDescription: String? { localizedDescription }
}

// MARK: - Export Result

/// Export result information
public struct ExportResult: Sendable {
    /// Output file URL
    public let outputURL: URL
    /// Output file size in bytes
    public let fileSize: UInt64
    /// Output duration in seconds
    public let duration: TimeInterval
    /// Preset used for export
    public let preset: ExportPreset
}

// MARK: - NSColor Extension

/// Extension for creating NSColor from hex strings
extension NSColor {
    /// Create NSColor from hex string (e.g., "#FFFFFF" or "FFFFFF")
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
