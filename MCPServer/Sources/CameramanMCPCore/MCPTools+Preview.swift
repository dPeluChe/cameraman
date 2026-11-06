//
//  MCPTools+Preview.swift
//  cameraman-mcp
//
//  preview_frame: lets an agent see the composited result instead of guessing from numbers.
//

import CoreGraphics
import EngineKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension MCPTools {
    func previewFrame(_ args: [String: Any]) async throws -> [[String: Any]] {
        let at = try args.num("at")
        let maxWidth = args.optNum("maxWidth") ?? 1280
        guard (320...1920).contains(maxWidth) else { throw MCPToolError("'maxWidth' must be between 320 and 1920.") }
        let project = try await loadProject(args)
        guard at >= 0, at <= project.timeline.duration else {
            throw MCPToolError("'at' must be within the timeline (0 to \(project.timeline.duration)).")
        }
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)

        let engine = PreviewEngine()
        try await engine.loadProject(project, projectDirectory: directory.path)
        let frame = try await engine.extractFrame(at: at)
        await engine.unloadProject()

        guard let data = Self.jpeg(frame, longestSide: maxWidth) else {
            throw MCPToolError("Could not encode the frame.")
        }
        return [["type": "image", "data": data.base64EncodedString(), "mimeType": "image/jpeg"]]
    }

    static func jpeg(_ image: CGImage, longestSide: Double) -> Data? {
        let scale = min(1, longestSide / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
