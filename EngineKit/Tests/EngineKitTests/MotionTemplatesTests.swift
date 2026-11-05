import XCTest
import AVFoundation
@testable import EngineKit

@MainActor
final class MotionTemplatesTests: XCTestCase {
    private func render(_ template: MotionTemplate, _ content: MotionTemplate.Content, duration: Double = 2) async throws -> URL {
        let html = try template.html(content, duration: duration)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        let result = try await MotionRenderer.render(html: html, to: url, options: MotionRenderOptions(width: 640, height: 360, fps: 10))
        XCTAssertEqual(result.frameCount, Int(duration * 10), "\(template) must end exactly at its duration")
        return url
    }

    private func coverage(_ url: URL, at seconds: Double) throws -> Double {
        MotionTestSupport.coverage(try MotionTestSupport.frame(of: url, at: seconds))
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
        XCTAssertThrowsError(try MotionTemplate.lowerThird.html(.init())) { XCTAssertTrue("\($0.localizedDescription)".contains("title")) }
        XCTAssertThrowsError(try MotionTemplate.stat.html(.init(value: "lots")))
        XCTAssertThrowsError(try MotionTemplate.barChart.html(.init(labels: ["a"], values: [1, 2])))
        XCTAssertThrowsError(try MotionTemplate.barChart.html(.init(labels: ["a"], values: [-1])))
    }

    func testTextCannotBreakOutOfThePage() throws {
        let hostile = "</div><script>alert(1)</script>\"'&"
        let html = try MotionTemplate.lowerThird.html(.init(title: hostile, subtitle: hostile))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        let stat = try MotionTemplate.stat.html(.init(title: hostile, value: "9\"</script><script>x=1//"))
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
        XCTAssertEqual(MotionTemplate.safeColor("34c759"), "#0A84FF", "CSS needs the #")
    }

    func testHugeBarValueIsRejected() {
        XCTAssertThrowsError(try MotionTemplate.barChart.html(.init(title: "x", labels: ["a"], values: [1e300])))
    }

    func testLargestBarValueStaysAPlainNumber() throws {
        let html = try MotionTemplate.barChart.html(.init(title: "x", labels: ["a"], values: [9e14]))
        XCTAssertTrue(html.contains("900000000000000"))
    }

    func testStatCommasMeanThousandsOnly() throws {
        let thousands = try XCTUnwrap(MotionTemplate.parseStat("1,250 users"))
        XCTAssertEqual(thousands.target, 1250)
        XCTAssertTrue(thousands.grouped)
        XCTAssertEqual(thousands.suffix, " users")
        let decimalComma = try XCTUnwrap(MotionTemplate.parseStat("1,5M"))
        XCTAssertEqual(decimalComma.target, 1)
        XCTAssertEqual(decimalComma.suffix, ",5M")
        XCTAssertFalse(decimalComma.grouped)
    }

    func testJSStringCannotOpenOrCloseMarkup() {
        let literal = MotionTemplate.jsString("<!-- <script> </script>")
        XCTAssertFalse(literal.contains("<"))
    }
}
