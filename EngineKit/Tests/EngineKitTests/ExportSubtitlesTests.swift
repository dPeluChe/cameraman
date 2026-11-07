import XCTest
@testable import EngineKit

final class ExportSubtitlesTests: XCTestCase {
    func testAnExportLeavesSubtitlesOutOnlyWhenAsked() {
        var project = Project(
            projectId: UUID(), name: "subtitles", timeline: Project.Timeline(duration: 5, tracks: []),
            canvas: Project.Canvas(format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                                   background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                                   layout: Project.Canvas.Layout(type: "pip", camera: nil)))
        let cue = Project.Overlay(
            id: UUID(), type: .text, start: 0, end: 2,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.9, scale: 1, rotation: 0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 0, shadow: false, font: "Helvetica", size: 24,
                                         color: "#FFFFFF", bg: nil, text: "Hello"),
            animation: nil)
        project.subtitles = [cue]
        project.overlays = [cue]

        XCTAssertEqual(project.prepared(for: ExportOptions()).subtitles.count, 1)
        let without = project.prepared(for: ExportOptions(includeSubtitles: false))
        XCTAssertTrue(without.subtitles.isEmpty)
        XCTAssertEqual(without.overlays.count, 1, "Other overlays still burn")
        XCTAssertEqual(without.overlayConfigs.count, 1, "The compositor's static-clip path sees no subtitles either")
    }
}
