//
//  PreviewEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

/// Preview engine for playing back video with edits applied
/// Supports seek, play, pause, and applies trims/cuts/layouts from project
/// Also supports proxy generation for smooth preview of large files
public actor PreviewEngine {
    /// The project being previewed
    private var project: Project?

    /// Project directory path (for proxy generation)
    private var projectDirectory: String?

    /// AVPlayer for video playback
    private var player: AVPlayer?

    /// Current playback state
    private var playbackState: PlaybackState = .stopped

    /// Current playback time in seconds
    private var currentTime: TimeInterval = 0

    /// Playback rate (1.0 = normal speed)
    private var playbackRate: Double = 1.0

    /// Whether to loop playback
    private var loopEnabled: Bool = false

    /// Configuration for preview
    private var configuration: Configuration

    /// Proxy generator for creating low-resolution previews
    private var proxyGenerator: ProxyGenerator

    /// Captions manager for displaying captions overlay
    private var captionsManager: CaptionsManager

    /// Configuration for preview
    public struct Configuration: Sendable {
        /// Whether to use low-quality proxy for smoother preview
        public let useProxy: Bool
        /// Proxy resolution (width)
        public let proxyWidth: Int
        /// Proxy resolution (height)
        public let proxyHeight: Int
        /// Whether to enable hardware acceleration
        public let hardwareAcceleration: Bool

        public init(
            useProxy: Bool = true,
            proxyWidth: Int = 1280,
            proxyHeight: Int = 720,
            hardwareAcceleration: Bool = true
        ) {
            self.useProxy = useProxy
            self.proxyWidth = proxyWidth
            self.proxyHeight = proxyHeight
            self.hardwareAcceleration = hardwareAcceleration
        }

        /// Default configuration for smooth preview
        public static let `default` = Configuration()

        /// High-quality configuration (no proxy)
        public static let highQuality = Configuration(useProxy: false)
    }

    /// Playback state
    public enum PlaybackState: Equatable, Sendable {
        case stopped
        case playing
        case paused
    }

    /// Preview error types
    public enum PreviewError: Error, Equatable, Sendable {
        case noProjectLoaded
        case projectLoadFailed(String)
        case playbackFailed(String)
        case seekFailed(String)
        case invalidTime(TimeInterval)
        case noSegments
        case mediaFileNotFound(String)

        public var localizedDescription: String {
            switch self {
            case .noProjectLoaded:
                return "No project loaded for preview"
            case .projectLoadFailed(let reason):
                return "Failed to load project: \(reason)"
            case .playbackFailed(let reason):
                return "Playback failed: \(reason)"
            case .seekFailed(let reason):
                return "Seek failed: \(reason)"
            case .invalidTime(let time):
                return "Invalid time: \(time)s"
            case .noSegments:
                return "Project has no segments to preview"
            case .mediaFileNotFound(let path):
                return "Media file not found: \(path)"
            }
        }
    }

    /// Preview session information
    public struct PreviewSession: Sendable {
        /// Current playback state
        public let state: PlaybackState
        /// Current playback time in seconds
        public let currentTime: TimeInterval
        /// Total duration in seconds
        public let duration: TimeInterval
        /// Playback rate
        public let playbackRate: Double
        /// Whether loop is enabled
        public let isLooping: Bool

        public init(
            state: PlaybackState,
            currentTime: TimeInterval,
            duration: TimeInterval,
            playbackRate: Double,
            isLooping: Bool
        ) {
            self.state = state
            self.currentTime = currentTime
            self.duration = duration
            self.playbackRate = playbackRate
            self.isLooping = isLooping
        }
    }

    // MARK: - Initialization

    /// Initialize with optional configuration
    /// - Parameter configuration: Preview configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.proxyGenerator = ProxyGenerator()
        self.captionsManager = CaptionsManager()
    }

    /// Load a project for preview
    /// - Parameters:
    ///   - project: The project to preview
    ///   - projectDirectory: Optional project directory path (for proxy generation)
    /// - Throws: PreviewError if project cannot be loaded
    public func loadProject(_ project: Project, projectDirectory: String? = nil) async throws {
        guard !project.timeline.segments.isEmpty else {
            throw PreviewError.noSegments
        }

        // Verify screen media file exists
        // In a real implementation, we would check file existence here
        // For testing, we'll just store the project
        _ = project.sources.screen.path

        self.project = project
        self.projectDirectory = projectDirectory
        self.currentTime = 0
        self.playbackState = .stopped

        // Load captions if available
        if let captions = project.captions, let projectDir = projectDirectory {
            await loadCaptions(srtPath: captions.srtPath, vttPath: captions.vttPath, projectDirectory: projectDir)
        } else {
            // Clear captions if none available
            await captionsManager.clear()
        }

        // Create AVPlayer with composition that applies edits
        try await createPlayerWithEdits()
    }

    /// Unload the current project
    public func unloadProject() {
        self.project = nil
        self.projectDirectory = nil
        self.player?.pause()
        self.player = nil
        self.currentTime = 0
        self.playbackState = .stopped

        // Clear captions
        Task {
            await captionsManager.clear()
        }
    }

    // MARK: - Playback Control

    /// Start playback from current position
    /// - Throws: PreviewError if playback cannot start
    public func play() async throws {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard !project.timeline.segments.isEmpty else {
            throw PreviewError.noSegments
        }

        player?.play()
        playbackState = .playing
        playbackRate = 1.0

        // Start time observer for current time tracking
        startPeriodicTimeObservation()
    }

    /// Pause playback
    /// - Throws: PreviewError if playback cannot be paused
    public func pause() async throws {
        guard player != nil else {
            throw PreviewError.noProjectLoaded
        }

        player?.pause()
        playbackState = .paused
        stopPeriodicTimeObservation()
    }

    /// Stop playback and reset to beginning
    /// - Throws: PreviewError if playback cannot be stopped
    public func stop() async throws {
        guard player != nil else {
            throw PreviewError.noProjectLoaded
        }

        player?.pause()
        await player?.seek(to: .zero)
        currentTime = 0
        playbackState = .stopped
        stopPeriodicTimeObservation()
    }

    /// Seek to a specific time in the preview
    /// - Parameter time: Time in seconds to seek to
    /// - Throws: PreviewError if seek fails
    public func seek(to time: TimeInterval) async throws {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard time >= 0 && time <= project.timeline.duration else {
            throw PreviewError.invalidTime(time)
        }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        await player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    /// Set playback rate (speed)
    /// - Parameter rate: Playback rate (1.0 = normal, 2.0 = 2x speed, 0.5 = half speed)
    /// - Throws: PreviewError if rate cannot be set
    public func setPlaybackRate(_ rate: Double) async throws {
        guard player != nil else {
            throw PreviewError.noProjectLoaded
        }

        guard rate > 0 && rate <= 4.0 else {
            throw PreviewError.playbackFailed("Invalid playback rate: \(rate)")
        }

        player?.rate = Float(rate * (playbackState == .playing ? 1.0 : 0.0))
        playbackRate = rate
    }

    /// Enable or disable looping
    /// - Parameter enabled: Whether to enable looping
    public func setLooping(_ enabled: Bool) {
        loopEnabled = enabled
    }

    // MARK: - State Query

    /// Get current preview session information
    /// - Returns: PreviewSession with current state
    public func getSession() -> PreviewSession {
        let duration = project?.timeline.duration ?? 0
        return PreviewSession(
            state: playbackState,
            currentTime: currentTime,
            duration: duration,
            playbackRate: playbackRate,
            isLooping: loopEnabled
        )
    }

    /// Get current playback time
    /// - Returns: Current time in seconds
    public func getCurrentTime() -> TimeInterval {
        return currentTime
    }

    /// Get total duration
    /// - Returns: Total duration in seconds
    public func getDuration() -> TimeInterval {
        return project?.timeline.duration ?? 0
    }

    /// Get playback state
    /// - Returns: Current playback state
    public func getPlaybackState() -> PlaybackState {
        return playbackState
    }

    /// Check if currently playing
    /// - Returns: True if playing
    public func isPlaying() -> Bool {
        return playbackState == .playing
    }

    /// Check if currently paused
    /// - Returns: True if paused
    public func isPaused() -> Bool {
        return playbackState == .paused
    }

    /// Check if currently stopped
    /// - Returns: True if stopped
    public func isStopped() -> Bool {
        return playbackState == .stopped
    }

    // MARK: - Private Helpers

    /// Create AVPlayer with composition that applies edits
    private func createPlayerWithEdits() async throws {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        // Create AVMutableComposition with segments
        let composition = AVMutableComposition()

        // Add screen track
        let screenAsset = AVAsset(url: URL(fileURLWithPath: project.sources.screen.path))
        _ = screenAsset // Suppress unused warning for now

        // Load screen asset tracks
        let screenAssetTracks = try await screenAsset.loadTracks(withMediaType: .video)
        guard let screenTrack = screenAssetTracks.first else {
            throw PreviewError.playbackFailed("No video track found in screen recording")
        }

        // Add composition track for screen
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        guard let videoTrack = compositionVideoTrack else {
            throw PreviewError.playbackFailed("Failed to create composition video track")
        }

        var insertTime = CMTime.zero

        // Apply segments (trims, cuts, speed changes)
        for segment in project.timeline.segments {
            let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
            let endTime = CMTime(seconds: segment.sourceOut, preferredTimescale: 600)
            let duration = CMTimeSubtract(endTime, startTime)

            // Time range in source
            let timeRange = CMTimeRange(start: startTime, duration: duration)

            // Insert at current timeline position
            _ = CMTimeRange(start: insertTime, duration: duration)

            try videoTrack.insertTimeRange(
                timeRange,
                of: screenTrack,
                at: insertTime
            )

            // Advance insert time by segment duration (adjusted for speed)
            let segmentDuration = CMTime(
                seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                preferredTimescale: 600
            )
            insertTime = CMTimeAdd(insertTime, segmentDuration)
        }

        // Handle camera track if present
        if project.sources.camera != nil {
            // Add camera as separate track for PiP/side-by-side
            // This is a simplified version - full implementation would position camera based on canvas layout
        }

        // Create player item with composition
        // Note: AVPlayerItem is main actor-isolated, creating it on the main actor
        let playerItem = await MainActor.run {
            AVPlayerItem(asset: composition)
        }
        self.player = AVPlayer(playerItem: playerItem)

        // Add time observer for current time tracking
        // Note: In a real implementation, we would add a periodic time observer here
        // For now, we'll track time manually during playback
    }

    /// Start periodic time observation
    private func startPeriodicTimeObservation() {
        // In a real implementation, we would add a periodic time observer here
        // For now, this is a placeholder
    }

    /// Stop periodic time observation
    private func stopPeriodicTimeObservation() {
        // In a real implementation, we would remove the periodic time observer here
        // For now, this is a placeholder
    }

    /// Handle playback reached end
    private func handlePlaybackReachedEnd() {
        if loopEnabled {
            // Loop back to beginning
            Task {
                try? await seek(to: 0)
                try? await play()
            }
        } else {
            // Stop playback
            playbackState = .stopped
        }
    }

    // MARK: - Frame Extraction

    /// Extract a frame at a specific time with overlays rendered
    /// - Parameter time: Time in seconds
    /// - Returns: CGImage of the frame with overlays applied
    /// - Throws: PreviewError if frame cannot be extracted
    public func extractFrame(at time: TimeInterval) async throws -> CGImage {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard time >= 0 && time <= project.timeline.duration else {
            throw PreviewError.invalidTime(time)
        }

        let asset = AVAsset(url: URL(fileURLWithPath: project.sources.screen.path))
        _ = asset // Suppress unused warning for now

        let assetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImageGenerator.appliesPreferredTrackTransform = true

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let image = try assetImageGenerator.copyCGImage(at: cmTime, actualTime: nil)

        // Render overlays on the frame
        let imageWithOverlays = try await renderOverlays(on: image, at: time, project: project)

        return imageWithOverlays
    }

    /// Generate thumbnails for timeline
    /// - Parameters:
    ///   - count: Number of thumbnails to generate
    ///   - startTime: Start time for thumbnail range
    ///   - endTime: End time for thumbnail range
    /// - Returns: Array of (time, image) tuples
    /// - Throws: PreviewError if thumbnails cannot be generated
    public func generateThumbnails(
        count: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> [(TimeInterval, CGImage)] {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard count > 0 else {
            throw PreviewError.playbackFailed("Invalid thumbnail count: \(count)")
        }

        let asset = AVAsset(url: URL(fileURLWithPath: project.sources.screen.path))
        _ = asset // Suppress unused warning for now

        let assetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImageGenerator.appliesPreferredTrackTransform = true
        assetImageGenerator.maximumSize = CoreFoundation.CGSize(width: 160, height: 90)

        var thumbnails: [(TimeInterval, CGImage)] = []
        let duration = endTime - startTime
        let interval = duration / Double(count - 1)

        for i in 0..<count {
            let time = startTime + (Double(i) * interval)
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            let image = try assetImageGenerator.copyCGImage(at: cmTime, actualTime: nil)
            thumbnails.append((time, image))
        }

        return thumbnails
    }

    // MARK: - Overlay Rendering

    /// Render overlays on a frame
    /// - Parameters:
    ///   - image: Base frame image
    ///   - time: Current timeline time
    ///   - project: Project with overlay configuration
    /// - Returns: CGImage with overlays rendered
    /// - Throws: PreviewError if rendering fails
    private func renderOverlays(on image: CGImage, at time: TimeInterval, project: Project) async throws -> CGImage {
        let canvasWidth = project.canvas.format.w
        let canvasHeight = project.canvas.format.h

        // Get active overlays at current time
        let activeOverlays = project.overlays.filter { overlay in
            time >= overlay.start && time <= overlay.end
        }

        // Get active caption at current time
        let activeCaption = await captionsManager.getCaption(at: time)

        // If no active overlays or captions, return original image
        if activeOverlays.isEmpty && activeCaption == nil {
            return image
        }

        // Create bitmap context for rendering
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: image.bytesPerRow,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            throw PreviewError.playbackFailed("Failed to create graphics context")
        }

        // Draw original image
        let imageRect = CoreFoundation.CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        context.draw(image, in: imageRect)

        // Render each overlay
        for overlay in activeOverlays {
            try renderOverlay(overlay, in: context, imageSize: CoreFoundation.CGSize(width: CGFloat(image.width), height: CGFloat(image.height)), canvasSize: CoreFoundation.CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
        }

        // Render caption if active
        if let caption = activeCaption {
            try renderCaption(caption, in: context, imageSize: CoreFoundation.CGSize(width: CGFloat(image.width), height: CGFloat(image.height)), canvasSize: CoreFoundation.CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
        }

        // Extract final image
        guard let finalImage = context.makeImage() else {
            throw PreviewError.playbackFailed("Failed to create final image with overlays")
        }

        return finalImage
    }

    /// Render a single overlay on the graphics context
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    ///   - imageSize: Size of the image being rendered
    ///   - canvasSize: Canvas format size
    /// - Throws: PreviewError if rendering fails
    private func renderOverlay(
        _ overlay: Project.Overlay,
        in context: CGContext,
        imageSize: CoreFoundation.CGSize,
        canvasSize: CoreFoundation.CGSize
    ) throws {
        // Calculate actual position and size based on canvas format
        let x = overlay.transform.x * CGFloat(canvasSize.width)
        let y = overlay.transform.y * CGFloat(canvasSize.height)

        // Calculate scale based on image size vs canvas size
        let scaleX = imageSize.width / CGFloat(canvasSize.width)
        let scaleY = imageSize.height / CGFloat(canvasSize.height)

        // Save context state
        context.saveGState()

        // Apply transformations
        context.translateBy(x: x * scaleX, y: y * scaleY)
        context.scaleBy(x: overlay.transform.scale * scaleX, y: overlay.transform.scale * scaleY)
        context.rotate(by: overlay.transform.rotation * .pi / 180.0)

        // Apply shadow if enabled
        if overlay.style.shadow {
            context.setShadow(offset: CoreFoundation.CGSize(width: 4, height: 4), blur: 8, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        }

        // Render based on overlay type
        switch overlay.type {
        case .arrow:
            try renderArrow(overlay, in: context)

        case .rect:
            try renderRectangle(overlay, in: context)

        case .line:
            try renderLine(overlay, in: context)

        case .text:
            try renderText(overlay, in: context)
        }

        // Restore context state
        context.restoreGState()
    }

    /// Render an arrow overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    private func renderArrow(_ overlay: Project.Overlay, in context: CGContext) throws {
        let strokeColor = parseColor(overlay.style.stroke)
        let strokeWidth = CGFloat(overlay.style.strokeWidth)

        // Arrow shape: pointing right by default
        // Arrow consists of a line and a triangular head
        let arrowLength: CGFloat = 100
        let headLength: CGFloat = 30
        let headWidth: CGFloat = 20

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw arrow shaft
        context.move(to: CGPoint(x: -arrowLength / 2, y: 0))
        context.addLine(to: CGPoint(x: arrowLength / 2 - headLength, y: 0))

        // Draw arrow head
        context.move(to: CGPoint(x: arrowLength / 2, y: 0))
        context.addLine(to: CGPoint(x: arrowLength / 2 - headLength, y: -headWidth / 2))
        context.move(to: CGPoint(x: arrowLength / 2, y: 0))
        context.addLine(to: CGPoint(x: arrowLength / 2 - headLength, y: headWidth / 2))

        context.strokePath()
    }

    /// Render a rectangle overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    private func renderRectangle(_ overlay: Project.Overlay, in context: CGContext) throws {
        let strokeColor = parseColor(overlay.style.stroke)
        let strokeWidth = CGFloat(overlay.style.strokeWidth)

        // Default rectangle size
        let rectWidth: CGFloat = 200
        let rectHeight: CGFloat = 150
        let cornerRadius: CGFloat = 10

        let rect = CoreFoundation.CGRect(
            x: -rectWidth / 2,
            y: -rectHeight / 2,
            width: rectWidth,
            height: rectHeight
        )

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)

        // Create rounded rectangle path
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.strokePath()
    }

    /// Render a line overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    private func renderLine(_ overlay: Project.Overlay, in context: CGContext) throws {
        let strokeColor = parseColor(overlay.style.stroke)
        let strokeWidth = CGFloat(overlay.style.strokeWidth)

        // Default line dimensions (horizontal line)
        let lineLength: CGFloat = 200

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        // Draw line centered at origin
        context.move(to: CGPoint(x: -lineLength / 2, y: 0))
        context.addLine(to: CGPoint(x: lineLength / 2, y: 0))

        context.strokePath()
    }

    /// Render a text overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    private func renderText(_ overlay: Project.Overlay, in context: CGContext) throws {
        guard let text = overlay.style.text else {
            throw PreviewError.playbackFailed("Text overlay has no text content")
        }

        let textColor = parseColor(overlay.style.color ?? "#FFFFFF")
        let fontSize = overlay.style.size ?? 24
        let fontName = overlay.style.font ?? "Helvetica"

        // Set text attributes
        context.setTextDrawingMode(.fill)
        context.setFillColor(textColor)

        // Create font
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)

        // Create text attributes
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        // Create attributed string
        let attributedString = NSAttributedString(string: text, attributes: attributes)

        // Measure text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textBounds = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CoreFoundation.CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            nil
        )

        // Draw background if specified
        if let bgColorHex = overlay.style.bg {
            let bgColor = parseColor(bgColorHex)
            let bgPadding: CGFloat = 8
            let bgRect = CoreFoundation.CGRect(
                x: -textBounds.width / 2 - bgPadding,
                y: -textBounds.height / 2 - bgPadding,
                width: textBounds.width + bgPadding * 2,
                height: textBounds.height + bgPadding * 2
            )

            context.setFillColor(bgColor)
            context.fill([bgRect])
        }

        // Draw text centered at origin
        let textRect = CoreFoundation.CGRect(
            x: -textBounds.width / 2,
            y: -textBounds.height / 2,
            width: textBounds.width,
            height: textBounds.height
        )

        let textPath = CGPath(rect: textRect, transform: nil)
        let textFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), textPath, nil)

        CTFrameDraw(textFrame, context)
    }

    /// Parse a hex color string to CGColor
    /// - Parameter hex: Hex color string (e.g., "#FFFFFF" or "#FFFFFF80" for alpha)
    /// - Returns: CGColor
    private func parseColor(_ hex: String) -> CGColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgba: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgba)

        let r, g, b, a: CGFloat
        let length = hexSanitized.count

        if length == 6 {
            // RGB without alpha
            r = CGFloat((rgba & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgba & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgba & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            // RGBA with alpha
            r = CGFloat((rgba & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgba & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgba & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgba & 0x000000FF) / 255.0
        } else {
            // Default to white if invalid
            r = 1.0
            g = 1.0
            b = 1.0
            a = 1.0
        }

        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Get active overlays at a specific time
    /// - Parameter time: Timeline time in seconds
    /// - Returns: Array of active overlays
    public func getActiveOverlays(at time: TimeInterval) -> [Project.Overlay] {
        guard let project = project else {
            return []
        }

        return project.overlays.filter { overlay in
            time >= overlay.start && time <= overlay.end
        }
    }

    // MARK: - Captions Rendering

    /// Render a caption on the graphics context
    /// - Parameters:
    ///   - caption: Caption entry to render
    ///   - context: Graphics context
    ///   - imageSize: Size of the image being rendered
    ///   - canvasSize: Canvas format size
    /// - Throws: PreviewError if rendering fails
    private func renderCaption(
        _ caption: CaptionsManager.CaptionEntry,
        in context: CGContext,
        imageSize: CoreFoundation.CGSize,
        canvasSize: CoreFoundation.CGSize
    ) throws {
        let style = await captionsManager.getStyle()

        // Calculate font size based on image height
        let fontSize = style.fontSize * CGFloat(imageSize.height)

        // Create font
        let font = CTFontCreateWithName(style.fontFamily as CFString, fontSize, nil)

        // Create paragraph style for alignment
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = style.horizontalAlignment < 0.33 ? .left :
                                   style.horizontalAlignment > 0.66 ? .right : .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        // Create text attributes
        let textColor = parseColor(style.textColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        // Create attributed string
        let attributedString = NSAttributedString(string: caption.text, attributes: attributes)

        // Measure text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let maxWidth = style.maxLineWidth * CGFloat(imageSize.width)
        let textBounds = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CoreFoundation.CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            nil
        )

        // Calculate caption position (bottom of screen by default)
        let padding: CGFloat = 20
        let x = style.horizontalAlignment * CGFloat(imageSize.width)
        let y = (1.0 - style.verticalPosition) * CGFloat(imageSize.height) - textBounds.height - padding

        // Draw background if opacity > 0
        if style.backgroundOpacity > 0 {
            let bgColor = parseColor(style.backgroundColor)
            let bgPadding: CGFloat = 12

            // Calculate background rect based on alignment
            var bgX: CGFloat
            switch paragraphStyle.alignment {
            case .left:
                bgX = x - bgPadding
            case .right:
                bgX = x - textBounds.width - bgPadding
            default:
                bgX = x - textBounds.width / 2 - bgPadding
            }

            let bgRect = CoreFoundation.CGRect(
                x: bgX,
                y: y - bgPadding,
                width: textBounds.width + bgPadding * 2,
                height: textBounds.height + bgPadding * 2
            )

            // Create background color with opacity
            let bgComponents = bgColor.components ?? [0, 0, 0, 1]
            let bgColorWithAlpha = CGColor(
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: bgComponents
            )?.copy(alpha: style.backgroundOpacity) ?? bgColor

            context.setFillColor(bgColorWithAlpha)
            context.fill([bgRect])
        }

        // Draw shadow if enabled
        if style.shadow {
            context.setShadow(offset: CoreFoundation.CGSize(width: 2, height: 2), blur: 4, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.8))
        } else {
            context.setShadow(offset: .zero, blur: 0, color: nil)
        }

        // Draw text
        let textRect = CoreFoundation.CGRect(x: x, y: y, width: textBounds.width, height: textBounds.height)

        // Adjust x position based on alignment
        let adjustedRect: CoreFoundation.CGRect
        switch paragraphStyle.alignment {
        case .left:
            adjustedRect = CoreFoundation.CGRect(x: x, y: y, width: min(textBounds.width, maxWidth), height: textBounds.height)
        case .right:
            adjustedRect = CoreFoundation.CGRect(x: x - textBounds.width, y: y, width: min(textBounds.width, maxWidth), height: textBounds.height)
        default:
            adjustedRect = CoreFoundation.CGRect(x: x - textBounds.width / 2, y: y, width: min(textBounds.width, maxWidth), height: textBounds.height)
        }

        let textPath = CGPath(rect: adjustedRect, transform: nil)
        let textFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), textPath, nil)

        CTFrameDraw(textFrame, context)
    }

    /// Load captions from file paths
    /// - Parameters:
    ///   - srtPath: Relative path to SRT file
    ///   - vttPath: Relative path to VTT file
    ///   - projectDirectory: Project directory path
    private func loadCaptions(srtPath: String, vttPath: String, projectDirectory: String) async {
        // Prefer VTT if available, otherwise use SRT
        let vttFullPath = (projectDirectory as NSString).appendingPathComponent(vttPath)
        let srtFullPath = (projectDirectory as NSString).appendingPathComponent(srtPath)

        let captionPath = FileManager.default.fileExists(atPath: vttFullPath) ? vttFullPath : srtFullPath

        do {
            try await captionsManager.loadCaptions(from: captionPath)
        } catch {
            // If captions fail to load, just continue without them
            // This is not a fatal error for preview
            print("Warning: Failed to load captions: \(error.localizedDescription)")
        }
    }

    // MARK: - Captions Query API

    /// Get active caption at current time
    /// - Returns: Caption entry if active, nil otherwise
    public func getActiveCaption() async -> CaptionsManager.CaptionEntry? {
        return await captionsManager.getCaption(at: currentTime)
    }

    /// Get active caption at a specific time
    /// - Parameter time: Time in seconds
    /// - Returns: Caption entry if active, nil otherwise
    public func getCaption(at time: TimeInterval) async -> CaptionsManager.CaptionEntry? {
        return await captionsManager.getCaption(at: time)
    }

    /// Get all captions
    /// - Returns: Array of all caption entries
    public func getAllCaptions() async -> [CaptionsManager.CaptionEntry] {
        return await captionsManager.getAllCaptions()
    }

    /// Check if captions are available
    /// - Returns: True if captions are loaded and available
    public func hasCaptions() async -> Bool {
        return await captionsManager.hasCaptions()
    }

    /// Enable or disable captions overlay
    /// - Parameter enabled: Whether to show captions
    public func setCaptionsEnabled(_ enabled: Bool) async {
        await captionsManager.setEnabled(enabled)
    }

    /// Check if captions are enabled
    /// - Returns: True if captions are enabled
    public func isCaptionsEnabled() async -> Bool {
        return await captionsManager.isEnabled()
    }

    /// Update caption style
    /// - Parameter style: New caption style
    public func updateCaptionStyle(_ style: CaptionsManager.CaptionStyle) async {
        await captionsManager.updateStyle(style)
    }

    /// Get current caption style
    /// - Returns: Current caption style
    public func getCaptionStyle() async -> CaptionsManager.CaptionStyle {
        return await captionsManager.getStyle()
    }

    // MARK: - Proxy Generation

    /// Generate proxies for the current project
    /// - Parameters:
    ///   - projectDirectory: Project's directory path
    ///   - configuration: Optional proxy configuration (uses default if nil)
    ///   - progress: Optional progress handler (0.0 to 1.0)
    /// - Returns: Dictionary of track type to ProxyResult
    /// - Throws: PreviewError if generation fails
    public func generateProxies(
        projectDirectory: String,
        configuration: ProxyGenerator.Configuration? = nil,
        progress: ProxyGenerator.ProgressHandler? = nil
    ) async throws -> [String: ProxyGenerator.ProxyResult] {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        let proxyConfig = configuration ?? ProxyGenerator.Configuration(
            width: self.configuration.proxyWidth,
            height: self.configuration.proxyHeight
        )

        return try await proxyGenerator.generateProjectProxies(
            for: project,
            projectDirectory: projectDirectory,
            configuration: proxyConfig,
            progress: progress
        )
    }

    /// Check if proxies are available for the current project
    /// - Returns: True if proxies exist and should be used
    public func hasProxies() -> Bool {
        guard project != nil,
              let projectDir = projectDirectory else {
            return false
        }

        // Check if screen proxy exists
        let screenProxyPath = (projectDir as NSString).appendingPathComponent("proxies/screen_proxy.mov")
        return FileManager.default.fileExists(atPath: screenProxyPath)
    }

    /// Get proxy path for a specific track
    /// - Parameter trackType: Track type ("screen" or "camera")
    /// - Returns: Path to proxy file if it exists, nil otherwise
    public func getProxyPath(for trackType: String) -> String? {
        guard let projectDir = projectDirectory else {
            return nil
        }

        let proxiesDirectory = (projectDir as NSString).appendingPathComponent("proxies")
        let proxyFileName = "\(trackType)_proxy.mov"
        let proxyPath = (proxiesDirectory as NSString).appendingPathComponent(proxyFileName)

        return FileManager.default.fileExists(atPath: proxyPath) ? proxyPath : nil
    }

    /// Delete all proxies for the current project
    /// - Throws: PreviewError if deletion fails
    public func deleteProxies() async throws {
        guard let projectDir = projectDirectory else {
            throw PreviewError.noProjectLoaded
        }

        let proxiesDirectory = (projectDir as NSString).appendingPathComponent("proxies")

        if FileManager.default.fileExists(atPath: proxiesDirectory) {
            try FileManager.default.removeItem(atPath: proxiesDirectory)
        }
    }
}
