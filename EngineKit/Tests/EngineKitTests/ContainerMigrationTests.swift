import XCTest
@testable import EngineKit

final class ContainerMigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ path: String) -> String? {
        (try? Data(contentsOf: root.appendingPathComponent(path))).map { String(decoding: $0, as: UTF8.self) }
    }

    func testDataMovesOutAndNothingAlreadyThereIsOverwritten() throws {
        let old = "container/Library/Application Support/ProjectStudio"
        try write("a", "\(old)/Projects/A/project.json")
        try write("old b", "\(old)/Projects/B/project.json")
        try write("model", "container/Documents/huggingface/models/whisper/weights.bin")
        try write("take", "container/Documents/Recordings/recording_1/screen.mov")
        try write("new b", "support/Projects/B/project.json")

        let migration = ContainerMigration(container: root.appendingPathComponent("container"),
                                           support: root.appendingPathComponent("support"), bundleIdentifier: "dev.test")
        XCTAssertGreaterThan(migration.run(importingPreferencesInto: nil), 0)

        XCTAssertEqual(read("support/Projects/A/project.json"), "a")
        XCTAssertEqual(read("support/Projects/B/project.json"), "new b", "What is already outside wins")
        XCTAssertEqual(read("support/Models/models/whisper/weights.bin"), "model")
        XCTAssertEqual(read("support/Recordings/recording_1/screen.mov"), "take")
        XCTAssertNil(read("\(old)/Projects/A/project.json"))
        XCTAssertEqual(migration.run(importingPreferencesInto: nil), 0, "A second run finds nothing new to move")
    }

    func testPreferencesFillOnlyKeysNotSetYet() throws {
        let id = "dev.test.migration"
        let plist = root.appendingPathComponent("container/Library/Preferences/\(id).plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(NSDictionary(dictionary: ["mcp.host.enabled": true, "theme": "dark"]).write(to: plist, atomically: true))

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "migration-\(UUID().uuidString)"))
        defaults.set("light", forKey: "theme")
        ContainerMigration(container: root.appendingPathComponent("container"), support: root.appendingPathComponent("support"),
                           bundleIdentifier: id).run(importingPreferencesInto: defaults)

        XCTAssertTrue(defaults.bool(forKey: "mcp.host.enabled"))
        XCTAssertEqual(defaults.string(forKey: "theme"), "light")
    }
}
