//
//  ImageOverlayRenderer.swift
//  EngineKit
//
//  Image overlay rendering utilities
//

import Foundation
import CoreGraphics
import ImageIO

public final class ImageOverlayRenderer: @unchecked Sendable {
    private var cache: [String: CGImage] = [:]
    private let lock = NSLock()
    public let projectDirectory: URL?

    public init(projectDirectory: URL?) {
        self.projectDirectory = projectDirectory
    }

    /// Render an image overlay
    public func render(
        mediaItem: Project.MediaItem,
        in context: CGContext,
        canvasSize: CGSize,
        imageSize: CGSize
    ) throws {
        guard mediaItem.type == .image else { return }

        guard let overlayImage = loadImage(path: mediaItem.path) else { return }

        let position = mediaItem.position ?? .defaultOverlay

        let x = CGFloat(position.x) * canvasSize.width
        let y = (1 - CGFloat(position.y) - CGFloat(position.h)) * canvasSize.height
        let w = CGFloat(position.w) * canvasSize.width
        let h = CGFloat(position.h) * canvasSize.height

        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height

        let drawRect = CGRect(x: x * scaleX, y: y * scaleY, width: w * scaleX, height: h * scaleY)
        context.draw(overlayImage, in: drawRect)
    }

    /// Load image with thread-safe caching
    private func loadImage(path: String) -> CGImage? {
        lock.lock()
        if let cached = cache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let projectDir = projectDirectory else { return nil }
        let imageURL = projectDir.appendingPathComponent(path)

        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        lock.lock()
        if cache.count >= 10, let oldest = cache.keys.first {
            cache.removeValue(forKey: oldest)
        }
        cache[path] = cgImage
        lock.unlock()

        return cgImage
    }
}
