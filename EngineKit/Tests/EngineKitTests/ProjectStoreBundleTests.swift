//
//  ProjectStoreBundleTests.swift
//  EngineKitTests
//
//  Export/import project bundles: essentials copied, regenerables skipped,
//  imports get a fresh id.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class ProjectStoreBundleTests: XCTestCase {
    var tempDirectory: URL!
    var sut: ProjectStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineKitBundleTests_\(UUID().uuidString)", isDirectory: true)
        sut = ProjectStore(baseDirectory: tempDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func makeProjectWithMedia(name: String) async throws -> ProjectId {
        let projectId = try await sut.createEmptyProject(name: name)
        let dir = tempDirectory.appendingPathComponent(projectId.uuidString)
        try Data("video".utf8).write(to: dir.appendingPathComponent("sources/clip.mov"))
        try Data("cache".utf8).write(to: dir.appendingPathComponent("cache/thumbnails/t1.jpg"))
        try Data("render".utf8).write(to: dir.appendingPathComponent("renders/out.mp4"))
        return projectId
    }

    func testExportBundle_copiesEssentials_skipsRegenerables() async throws {
        let projectId = try await makeProjectWithMedia(name: "Demo")
        let exportDir = tempDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let bundle = try await sut.exportProjectBundle(projectId: projectId, to: exportDir)

        XCTAssertEqual(bundle.lastPathComponent, "Demo.cameramanproject")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("project.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("sources/clip.mov").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("cache").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("renders").path))
    }

    func testImportBundle_createsNewProjectWithFreshId() async throws {
        let projectId = try await makeProjectWithMedia(name: "Demo")
        let exportDir = tempDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let bundle = try await sut.exportProjectBundle(projectId: projectId, to: exportDir)

        let importedId = try await sut.importProjectBundle(from: bundle)

        XCTAssertNotEqual(importedId, projectId)
        let imported = try await sut.loadProject(projectId: importedId)
        XCTAssertEqual(imported.name, "Demo")
        XCTAssertEqual(imported.projectId, importedId)
        let dir = tempDirectory.appendingPathComponent(importedId.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sources/clip.mov").path))
        // Regenerable structure restored for future renders/proxies
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("renders").path))
    }

    func testImportBundle_rejectsNonProjectFolder() async throws {
        let bogus = tempDirectory.appendingPathComponent("not-a-project", isDirectory: true)
        try FileManager.default.createDirectory(at: bogus, withIntermediateDirectories: true)
        do {
            _ = try await sut.importProjectBundle(from: bogus)
            XCTFail("Expected import of non-project folder to throw")
        } catch { /* expected */ }
    }
}
