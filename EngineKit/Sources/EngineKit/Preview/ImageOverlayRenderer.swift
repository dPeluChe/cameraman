//
//  ImageOverlayRenderer.swift
//  EngineKit
//
//  Image overlay rendering utilities
//

import Foundation
import CoreGraphics
import ImageIO

public final class ImageOverlayRenderer {
    private var cache: [String: CGImage] = [:]
    private let projectDirectory: URL?

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

        let position = mediaItem.position ?? Project.MediaPosition.centered(w: 0.25, h: 0.25)

        let x = CGFloat(position.x) * canvasSize.width
        let y = (1 - CGFloat(position.y) - CGFloat(position.h)) * canvasSize.height
        let w = CGFloat(position.w) * canvasSize.width
        let h = CGFloat(position.h) * canvasSize.height

        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height

        let drawRect = CGRect(x: x * scaleX, y: y * scaleY, width: w * scaleX, height: h * scaleY)
        context.draw(overlayImage, in: drawRect)
    }

    /// Load image with caching
    private func loadImage(path: String) -> CGImage? {
        if let cached = cache[path] {
            return cached
        }

        guard let projectDir = projectDirectory else { return nil }
        let imageURL = projectDir.appendingPathComponent(path)

        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        if cache.count > 10 {
            cache.removeAll()
        }
        cache[path] = cgImage

        return cgImage
    }
}
