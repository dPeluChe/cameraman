import XCTest
@testable import EngineKit

final class ExportFilenameTests: XCTestCase {
    private func name(_ supplied: String?, _ ext: String = "mp4") -> String {
        ExportOptions(outputFilename: supplied).resolvedFilename(fileExtension: ext, timestamp: "T")
    }

    func testAddsTheExtensionWhenMissing() {
        XCTAssertEqual(name("demo"), "demo.mp4")
        XCTAssertEqual(name("demo", "gif"), "demo.gif")
    }

    func testKeepsAnExtensionThatAlreadyMatches() {
        XCTAssertEqual(name("demo.mp4"), "demo.mp4")
        XCTAssertEqual(name("Demo.MP4"), "Demo.MP4")
    }

    func testAppendsWhenTheNameHasADifferentExtension() {
        // "take.1" is a name, not a format: the real extension is still needed.
        XCTAssertEqual(name("take.1"), "take.1.mp4")
        XCTAssertEqual(name("clip.mov"), "clip.mov.mp4")
    }

    func testDefaultsToATimestampedName() {
        XCTAssertEqual(name(nil), "export_T.mp4")
        XCTAssertEqual(name(""), "export_T.mp4")
    }

    /// A name from an MCP argument must not write outside the renders folder.
    func testPathComponentsCannotEscapeTheRendersFolder() {
        XCTAssertEqual(name("../../outside"), "outside.mp4")
        XCTAssertEqual(name("/etc/passwd"), "passwd.mp4")
        XCTAssertEqual(name("a/b/c.mp4"), "c.mp4")
        XCTAssertEqual(name(".."), "export_T.mp4")
        XCTAssertEqual(name("."), "export_T.mp4")
    }
}
