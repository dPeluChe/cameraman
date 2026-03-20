//
//  CaptionsManager.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19
//

import Foundation

/// CaptionsManager handles parsing and querying of caption files (SRT/VTT)
/// Used by PreviewEngine to display captions overlay during playback
public actor CaptionsManager {
    /// Loaded caption entries
    private var captions: [CaptionEntry] = []

    /// Caption style configuration
    private var style: CaptionStyle

    /// Whether captions are enabled
    private var captionsEnabled: Bool = true

    // MARK: - Initialization

    /// Initialize with empty captions
    /// - Parameter style: Caption style (uses default if not specified)
    public init(style: CaptionStyle = .default) {
        self.style = style
    }

    /// Initialize with captions from a file (async factory method)
    /// - Parameters:
    ///   - filePath: Path to caption file (SRT or VTT)
    ///   - style: Caption style (uses default if not specified)
    /// - Returns: A new CaptionsManager instance with loaded captions
    /// - Throws: CaptionsError if file cannot be loaded or parsed
    public static func load(from filePath: String, style: CaptionStyle = .default) async throws -> CaptionsManager {
        let manager = CaptionsManager(style: style)
        try await manager.loadCaptionsAsync(from: filePath)
        return manager
    }

    // MARK: - Loading Captions

    /// Load captions from a file
    /// - Parameter filePath: Path to caption file (SRT or VTT)
    /// - Throws: CaptionsError if file cannot be loaded or parsed
    public func loadCaptions(from filePath: String) throws {
        // Synchronous wrapper for compatibility
        let fileURL = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw CaptionsError.fileNotFound(filePath)
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Determine format from file extension
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        let format: CaptionFormat

        switch fileExtension {
        case "srt":
            format = .srt
        case "vtt":
            format = .vtt
        default:
            // Try to auto-detect from content
            if content.hasPrefix("WEBVTT") {
                format = .vtt
            } else {
                format = .srt
            }
        }

        // Parse based on format
        switch format {
        case .srt:
            self.captions = try parseSRT(content)
        case .vtt:
            self.captions = try parseVTT(content)
        }
    }

    /// Load captions from a file (async version)
    /// - Parameter filePath: Path to caption file (SRT or VTT)
    /// - Throws: CaptionsError if file cannot be loaded or parsed
    public func loadCaptionsAsync(from filePath: String) async throws {
        let fileURL = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw CaptionsError.fileNotFound(filePath)
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Determine format from file extension
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        let format: CaptionFormat

        switch fileExtension {
        case "srt":
            format = .srt
        case "vtt":
            format = .vtt
        default:
            // Try to auto-detect from content
            if content.hasPrefix("WEBVTT") {
                format = .vtt
            } else {
                format = .srt
            }
        }

        // Parse based on format
        switch format {
        case .srt:
            self.captions = try parseSRT(content)
        case .vtt:
            self.captions = try parseVTT(content)
        }
    }

    /// Parse SRT format captions
    /// - Parameter content: SRT file content
    /// - Returns: Array of caption entries
    /// - Throws: CaptionsError if parsing fails
    private func parseSRT(_ content: String) throws -> [CaptionEntry] {
        var entries: [CaptionEntry] = []
        let lines = content.components(separatedBy: .newlines)
        var currentLine = 0

        while currentLine < lines.count {
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if line.isEmpty {
                currentLine += 1
                continue
            }

            // Parse index
            guard let index = Int(line) else {
                throw CaptionsError.parseError("Invalid index at line \(currentLine + 1)")
            }

            currentLine += 1
            guard currentLine < lines.count else {
                throw CaptionsError.parseError("Incomplete entry at line \(currentLine)")
            }

            // Parse time range
            let timeLine = lines[currentLine].trimmingCharacters(in: .whitespaces)
            let timeComponents = timeLine.components(separatedBy: " --> ")
            guard timeComponents.count == 2 else {
                throw CaptionsError.parseError("Invalid time range at line \(currentLine + 1)")
            }

            let startTime = try parseSRTime(timeComponents[0])
            let endTime = try parseSRTime(timeComponents[1])

            currentLine += 1

            // Parse text (may span multiple lines)
            var textLines: [String] = []
            while currentLine < lines.count {
                let textLine = lines[currentLine].trimmingCharacters(in: .whitespaces)
                if textLine.isEmpty {
                    currentLine += 1
                    break
                }
                textLines.append(textLine)
                currentLine += 1
            }

            let text = textLines.joined(separator: "\n")
            entries.append(CaptionEntry(id: index, start: startTime, end: endTime, text: text))
        }

        guard !entries.isEmpty else {
            throw CaptionsError.emptyFile
        }

        return entries
    }

    /// Parse SRT time format (HH:MM:SS,mmm)
    /// - Parameter timeString: Time string
    /// - Returns: Time in seconds
    /// - Throws: CaptionsError if parsing fails
    private func parseSRTime(_ timeString: String) throws -> TimeInterval {
        let components = timeString.components(separatedBy: [":", ","])
        guard components.count == 4 else {
            throw CaptionsError.parseError("Invalid time format: \(timeString)")
        }

        guard let hours = TimeInterval(components[0]),
              let minutes = TimeInterval(components[1]),
              let seconds = TimeInterval(components[2]),
              let milliseconds = TimeInterval(components[3]) else {
            throw CaptionsError.parseError("Invalid time values: \(timeString)")
        }

        return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000
    }

    /// Parse VTT format captions
    /// - Parameter content: VTT file content
    /// - Returns: Array of caption entries
    /// - Throws: CaptionsError if parsing fails
    private func parseVTT(_ content: String) throws -> [CaptionEntry] {
        var entries: [CaptionEntry] = []
        let lines = content.components(separatedBy: .newlines)
        var currentLine = 0

        // Skip WEBVTT header
        guard currentLine < lines.count else {
            throw CaptionsError.emptyFile
        }

        let firstLine = lines[currentLine].trimmingCharacters(in: .whitespaces)
        guard firstLine == "WEBVTT" else {
            throw CaptionsError.invalidFormat("Missing WEBVTT header")
        }

        currentLine += 1

        // Skip empty lines after header
        while currentLine < lines.count && lines[currentLine].trimmingCharacters(in: .whitespaces).isEmpty {
            currentLine += 1
        }

        var index = 0

        while currentLine < lines.count {
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if line.isEmpty {
                currentLine += 1
                continue
            }

            // Skip optional cue identifier (line that doesn't contain "-->")
            if !line.contains("-->") {
                currentLine += 1
                continue
            }

            // Parse time range
            let timeComponents = line.components(separatedBy: " --> ")
            guard timeComponents.count == 2 else {
                throw CaptionsError.parseError("Invalid time range at line \(currentLine + 1)")
            }

            let startTime = try parseVTTTime(timeComponents[0])
            let endTime = try parseVTTTime(timeComponents[1])

            currentLine += 1

            // Parse text (may span multiple lines)
            var textLines: [String] = []
            while currentLine < lines.count {
                let textLine = lines[currentLine].trimmingCharacters(in: .whitespaces)
                if textLine.isEmpty {
                    currentLine += 1
                    break
                }
                textLines.append(textLine)
                currentLine += 1
            }

            let text = textLines.joined(separator: "\n")
            index += 1
            entries.append(CaptionEntry(id: index, start: startTime, end: endTime, text: text))
        }

        guard !entries.isEmpty else {
            throw CaptionsError.emptyFile
        }

        return entries
    }

    /// Parse VTT time format (HH:MM:SS.mmm)
    /// - Parameter timeString: Time string
    /// - Returns: Time in seconds
    /// - Throws: CaptionsError if parsing fails
    private func parseVTTTime(_ timeString: String) throws -> TimeInterval {
        let components = timeString.components(separatedBy: [":", "."])
        guard components.count == 4 else {
            throw CaptionsError.parseError("Invalid time format: \(timeString)")
        }

        guard let hours = TimeInterval(components[0]),
              let minutes = TimeInterval(components[1]),
              let seconds = TimeInterval(components[2]),
              let milliseconds = TimeInterval(components[3]) else {
            throw CaptionsError.parseError("Invalid time values: \(timeString)")
        }

        return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000
    }

    // MARK: - Querying Captions

    /// Get active caption at a specific time
    /// - Parameter time: Time in seconds
    /// - Returns: Caption entry if active, nil otherwise
    public func getCaption(at time: TimeInterval) -> CaptionEntry? {
        guard isEnabled() else { return nil }

        return captions.first { caption in
            time >= caption.start && time < caption.end
        }
    }

    /// Get all active captions at a specific time (for overlapping captions)
    /// - Parameter time: Time in seconds
    /// - Returns: Array of active caption entries
    public func getActiveCaptions(at time: TimeInterval) -> [CaptionEntry] {
        guard isEnabled() else { return [] }

        return captions.filter { caption in
            time >= caption.start && time < caption.end
        }
    }

    /// Get caption by index
    /// - Parameter index: Caption index (1-based)
    /// - Returns: Caption entry if found, nil otherwise
    public func getCaption(byIndex index: Int) -> CaptionEntry? {
        return captions.first { $0.id == index }
    }

    /// Get all captions
    /// - Returns: Array of all caption entries
    public func getAllCaptions() -> [CaptionEntry] {
        return captions
    }

    /// Get caption count
    /// - Returns: Number of caption entries
    public func getCaptionCount() -> Int {
        return captions.count
    }

    // MARK: - Style Management

    /// Get current caption style
    /// - Returns: Current caption style
    public func getStyle() -> CaptionStyle {
        return style
    }

    /// Update caption style
    /// - Parameter style: New caption style
    public func updateStyle(_ style: CaptionStyle) {
        self.style = style
    }

    // MARK: - Enable/Disable

    /// Enable or disable captions
    /// - Parameter enabled: Whether to enable captions
    public func setEnabled(_ enabled: Bool) {
        self.captionsEnabled = enabled
    }

    /// Check if captions are enabled
    /// - Returns: True if captions are enabled
    public func isEnabled() -> Bool {
        return captionsEnabled
    }

    // MARK: - Utility Methods

    /// Get time range of captions
    /// - Returns: Tuple of (start time, end time) or nil if no captions
    public func getTimeRange() -> (TimeInterval, TimeInterval)? {
        guard let first = captions.first, let last = captions.last else {
            return nil
        }
        return (first.start, last.end)
    }

    /// Clear all loaded captions
    public func clear() {
        captions.removeAll()
    }

    /// Check if captions are loaded
    /// - Returns: True if captions are loaded
    public func hasCaptions() -> Bool {
        return !captions.isEmpty
    }
}
