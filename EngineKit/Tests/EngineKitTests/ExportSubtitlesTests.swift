import AVFoundation
import XCTest
@testable import EngineKit

final class ExportSubtitlesTests: XCTestCase {
    func testSubtitlesBurnUnlessLeftOut() async throws {
        var project = Project(
            projectId: UUID(), name: "subtitles", timeline: Project.Timeline(duration: 5, tracks: []),
            canvas: Project.Canvas(format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                                   background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                                   layout: Project.Canvas.Layout(type: "pip", camera: nil)))
        project.subtitles = [Project.Overlay(
            id: UUID(), type: .text, start: 0, end: 2,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.9, scale: 1, rotation: 0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 0, shadow: false, font: "Helvetica", size: 24,
                                         color: "#FFFFFF", bg: nil, text: "Hello"),
            animation: nil)]
        let engine = ExportEngine(jobQueue: JobQueue(), projectStore: ProjectStore())

        let layer = { (include: Bool) in
            try await engine.createCombinedOverlayLayer(
                for: project, projectId: project.projectId, renderSize: CGSize(width: 1920, height: 1080),
                compositionDuration: CMTime(seconds: 5, preferredTimescale: 600), burnCaptions: false, includeSubtitles: include)
        }
        let withSubtitles = try await layer(true)
        let without = try await layer(false)
        XCTAssertNotNil(withSubtitles)
        XCTAssertNil(without, "Nothing else to draw, so no overlay layer")
        XCTAssertTrue(ExportOptions().includeSubtitles)
    }
}
