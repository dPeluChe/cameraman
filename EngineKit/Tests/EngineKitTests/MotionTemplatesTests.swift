import XCTest
import AVFoundation
@testable import EngineKit

@MainActor
final class MotionTemplatesTests: XCTestCase {
    private func render(_ template: MotionTemplate, _ content: MotionTemplate.Content, duration: Double = 2) async throws -> URL {
        let html = try template.html(content, duration: duration).get()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        let result = try await MotionRenderer.render(html: html, to: url, options: MotionRenderOptions(width: 640, height: 360, fps: 10))
        XCTAssertEqual(result.frameCount, Int(duration * 10), "\(template) must end exactly at its duration")
        return url
    }

    /// Share of pixels that are not fully transparent at `seconds`.
    private func coverage(_ url: URL, at seconds: Double) throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let visible = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 8 }.count
        return Double(visible) / Double(image.width * image.height)
    }

    func testEveryTemplateAppearsHoldsAndLeaves() async throws {
        let content = MotionTemplate.Content(title: "Ana Ruiz", subtitle: "CTO", value: "$1.2M",
                                             labels: ["Q1", "Q2", "Q3"], values: [10, 25, 18])
        for template in MotionTemplate.allCases {
            let url = try await render(template, content)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertGreaterThan(try coverage(url, at: 1.0), 0.01, "\(template) draws something while held")
            XCTAssertLessThan(try coverage(url, at: 1.9), try coverage(url, at: 1.0), "\(template) animates out at the end")
        }
    }

    func testMissingContentIsRejectedWithAReason() {
        XCTAssertEqual(MotionTemplate.lowerThird.html(.init()).failureValue, .missing("title"))
        XCTAssertNotNil(MotionTemplate.stat.html(.init(value: "lots")).failureValue)
        XCTAssertNotNil(MotionTemplate.barChart.html(.init(labels: ["a"], values: [1, 2])).failureValue)
        XCTAssertNotNil(MotionTemplate.barChart.html(.init(labels: ["a"], values: [-1])).failureValue)
    }

    func testTextCannotBreakOutOfThePage() throws {
        let hostile = "</div><script>alert(1)</script>\"'&"
        let html = try MotionTemplate.lowerThird.html(.init(title: hostile, subtitle: hostile)).get()
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        let stat = try MotionTemplate.stat.html(.init(title: hostile, value: "9\"</script><script>x=1//")).get()
        XCTAssertFalse(stat.contains("</script><script>x=1"))
    }

    func testStatParsing() {
        let money = MotionTemplate.parseStat("$1,200.50M")
        XCTAssertEqual(money?.prefix, "$")
        XCTAssertEqual(money?.suffix, "M")
        XCTAssertEqual(money?.target, 1200.5)
        XCTAssertEqual(money?.decimals, 2)
        XCTAssertEqual(MotionTemplate.parseStat("42%")?.suffix, "%")
        XCTAssertNil(MotionTemplate.parseStat("n/a"))
    }

    func testUnsafeColorFallsBackToTheDefault() {
        XCTAssertEqual(MotionTemplate.safeColor("red; } body { display:none"), "#0A84FF")
        XCTAssertEqual(MotionTemplate.safeColor("#34c759"), "#34c759")
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
