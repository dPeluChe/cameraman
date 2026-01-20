//
//  AppNavigationTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import App
@testable import EngineKit

@MainActor
final class AppNavigationTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: ProjectStore!
    private var library: ProjectLibrary!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        tempDirectory = tempDir.appendingPathComponent("AppNavigationTests_\(UUID().uuidString)", isDirectory: true)
        store = ProjectStore(baseDirectory: tempDirectory)
        library = ProjectLibrary(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    func testLoadProjectsPopulatesProjects() async throws {
        let projectId = try await createMockProject(name: "Sample Project", tags: ["demo"], duration: 60)
        let viewModel = AppNavigationViewModel(library: library)

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.projects.count, 1)
        XCTAssertEqual(viewModel.projects.first?.projectId, projectId)
    }

    func testLoadProjectsResetsMissingSelection() async throws {
        let viewModel = AppNavigationViewModel(library: library)
        viewModel.selectedItem = .project(UUID())

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.selectedItem, .recording)
    }

    func testLoadProjectsKeepsSelectedProject() async throws {
        let projectId = try await createMockProject(name: "Keep Me", tags: [], duration: 30)
        let viewModel = AppNavigationViewModel(library: library)
        viewModel.selectedItem = .project(projectId)

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.selectedItem, .project(projectId))
    }

    func testRenameProjectUpdatesProjectList() async throws {
        let projectId = try await createMockProject(name: "Old Name", tags: [], duration: 30)
        let viewModel = AppNavigationViewModel(library: library)

        await viewModel.loadProjects()
        await viewModel.renameProject(projectId: projectId, to: "New Name")

        let updatedProject = viewModel.projects.first { $0.projectId == projectId }
        XCTAssertEqual(updatedProject?.name, "New Name")
    }

    func testDeleteProjectRemovesFromList() async throws {
        let projectId = try await createMockProject(name: "Delete Me", tags: [], duration: 30)
        let viewModel = AppNavigationViewModel(library: library)

        await viewModel.loadProjects()
        await viewModel.deleteProject(projectId: projectId)

        XCTAssertFalse(viewModel.projects.contains { $0.projectId == projectId })
    }

    func testSetTagsUpdatesProjectList() async throws {
        let projectId = try await createMockProject(name: "Tagged", tags: ["old"], duration: 30)
        let viewModel = AppNavigationViewModel(library: library)

        await viewModel.loadProjects()
        await viewModel.setTags(projectId: projectId, tags: ["feature", "ui"])

        let updatedProject = viewModel.projects.first { $0.projectId == projectId }
        XCTAssertEqual(updatedProject?.tags, ["feature", "ui"])
    }

    func testParseTagsInputNormalizesTags() {
        let parsed = AppNavigationViewModel.parseTagsInput(" ui, , video,ui,  ")

        XCTAssertEqual(parsed, ["ui", "video"])
    }

    func testLibraryLayoutDefaultsToList() {
        let viewModel = AppNavigationViewModel(library: library)

        XCTAssertEqual(viewModel.libraryLayout, .list)
    }

    func testToggleLibraryLayoutCyclesLayouts() {
        let viewModel = AppNavigationViewModel(library: library)

        viewModel.toggleLibraryLayout()
        XCTAssertEqual(viewModel.libraryLayout, .grid)

        viewModel.toggleLibraryLayout()
        XCTAssertEqual(viewModel.libraryLayout, .list)
    }

    private func createMockProject(name: String, tags: [String], duration: TimeInterval) async throws -> ProjectId {
        let screenPath = tempDirectory.appendingPathComponent("test_screen_\(UUID().uuidString).mov")
        let telemetryPath = tempDirectory.appendingPathComponent("test_telemetry_\(UUID().uuidString).jsonl")

        FileManager.default.createFile(atPath: screenPath.path, contents: Data())
        FileManager.default.createFile(atPath: telemetryPath.path, contents: Data())

        let recordingResult = RecordingResult(
            screenPath: screenPath,
            cameraPath: nil,
            systemAudioPath: nil,
            micAudioPath: nil,
            telemetryPath: telemetryPath,
            duration: duration,
            startTime: Date(),
            endTime: Date().addingTimeInterval(duration)
        )

        return try await store.createProject(from: recordingResult, name: name, tags: tags)
    }
}
