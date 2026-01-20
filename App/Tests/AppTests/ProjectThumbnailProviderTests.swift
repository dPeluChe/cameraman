//
//  ProjectThumbnailProviderTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import AppKit
import XCTest
@testable import App

@MainActor
final class ProjectThumbnailProviderTests: XCTestCase {
    func testLoadImageReturnsNilForMissingPath() {
        XCTAssertNil(ProjectThumbnailProvider.loadImage(from: nil))
        XCTAssertNil(ProjectThumbnailProvider.loadImage(from: ""))
        XCTAssertNil(ProjectThumbnailProvider.loadImage(from: "/not/a/real/path.png"))
    }

    func testLoadImageLoadsImageFromDisk() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileUrl = tempDirectory.appendingPathComponent("thumbnail_\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 8, height: 8))

        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode test thumbnail")
            return
        }

        try pngData.write(to: fileUrl)
        defer {
            try? FileManager.default.removeItem(at: fileUrl)
        }

        let loadedImage = ProjectThumbnailProvider.loadImage(from: fileUrl.path)

        XCTAssertNotNil(loadedImage)
    }
}
