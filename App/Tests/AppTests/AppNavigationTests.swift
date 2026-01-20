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

    // MARK: - Sorting Tests

    func testSortByDateUpdatedDescending() async throws {
        // Create projects with different update times
        let projectId1 = try await createMockProject(name: "Project A", tags: [], duration: 30)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay

        let projectId2 = try await createMockProject(name: "Project B", tags: [], duration: 30)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay

        let projectId3 = try await createMockProject(name: "Project C", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .dateUpdated
        viewModel.sortDirectionAscending = false

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.count, 3)
        XCTAssertEqual(viewModel.filteredProjects[0].projectId, projectId3)
        XCTAssertEqual(viewModel.filteredProjects[1].projectId, projectId2)
        XCTAssertEqual(viewModel.filteredProjects[2].projectId, projectId1)
    }

    func testSortByDateUpdatedAscending() async throws {
        let projectId1 = try await createMockProject(name: "Project A", tags: [], duration: 30)
        try await Task.sleep(nanoseconds: 100_000_000)

        let projectId2 = try await createMockProject(name: "Project B", tags: [], duration: 30)
        try await Task.sleep(nanoseconds: 100_000_000)

        let projectId3 = try await createMockProject(name: "Project C", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .dateUpdated
        viewModel.sortDirectionAscending = true

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.count, 3)
        XCTAssertEqual(viewModel.filteredProjects[0].projectId, projectId1)
        XCTAssertEqual(viewModel.filteredProjects[1].projectId, projectId2)
        XCTAssertEqual(viewModel.filteredProjects[2].projectId, projectId3)
    }

    func testSortByNameAscending() async throws {
        try await createMockProject(name: "Zulu", tags: [], duration: 30)
        try await createMockProject(name: "Alpha", tags: [], duration: 30)
        try await createMockProject(name: "Mike", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .name
        viewModel.sortDirectionAscending = true

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["Alpha", "Mike", "Zulu"])
    }

    func testSortByNameDescending() async throws {
        try await createMockProject(name: "Zulu", tags: [], duration: 30)
        try await createMockProject(name: "Alpha", tags: [], duration: 30)
        try await createMockProject(name: "Mike", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .name
        viewModel.sortDirectionAscending = false

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["Zulu", "Mike", "Alpha"])
    }

    func testSortByNameCaseInsensitive() async throws {
        try await createMockProject(name: "apple", tags: [], duration: 30)
        try await createMockProject(name: "Banana", tags: [], duration: 30)
        try await createMockProject(name: "CHERRY", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .name
        viewModel.sortDirectionAscending = true

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["apple", "Banana", "CHERRY"])
    }

    func testSortByDurationAscending() async throws {
        try await createMockProject(name: "Long", tags: [], duration: 300)
        try await createMockProject(name: "Short", tags: [], duration: 30)
        try await createMockProject(name: "Medium", tags: [], duration: 120)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .duration
        viewModel.sortDirectionAscending = true

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["Short", "Medium", "Long"])
        XCTAssertEqual(viewModel.filteredProjects[0].duration, 30)
        XCTAssertEqual(viewModel.filteredProjects[1].duration, 120)
        XCTAssertEqual(viewModel.filteredProjects[2].duration, 300)
    }

    func testSortByDurationDescending() async throws {
        try await createMockProject(name: "Long", tags: [], duration: 300)
        try await createMockProject(name: "Short", tags: [], duration: 30)
        try await createMockProject(name: "Medium", tags: [], duration: 120)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .duration
        viewModel.sortDirectionAscending = false

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["Long", "Medium", "Short"])
        XCTAssertEqual(viewModel.filteredProjects[0].duration, 300)
        XCTAssertEqual(viewModel.filteredProjects[1].duration, 120)
        XCTAssertEqual(viewModel.filteredProjects[2].duration, 30)
    }

    func testSortByDateCreated() async throws {
        let projectId1 = try await createMockProject(name: "First", tags: [], duration: 30)
        try await Task.sleep(nanoseconds: 100_000_000)

        let projectId2 = try await createMockProject(name: "Second", tags: [], duration: 30)
        try await Task.sleep(nanoseconds: 100_000_000)

        let projectId3 = try await createMockProject(name: "Third", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .dateCreated
        viewModel.sortDirectionAscending = true

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.count, 3)
        XCTAssertEqual(viewModel.filteredProjects[0].projectId, projectId1)
        XCTAssertEqual(viewModel.filteredProjects[1].projectId, projectId2)
        XCTAssertEqual(viewModel.filteredProjects[2].projectId, projectId3)
    }

    func testSetSortOption() async throws {
        try await createMockProject(name: "Project", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.sortOption, .dateUpdated)

        viewModel.setSortOption(.name)
        XCTAssertEqual(viewModel.sortOption, .name)

        viewModel.setSortOption(.duration)
        XCTAssertEqual(viewModel.sortOption, .duration)
    }

    func testToggleSortDirection() async throws {
        try await createMockProject(name: "Project", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        await viewModel.loadProjects()

        XCTAssertFalse(viewModel.sortDirectionAscending)

        viewModel.toggleSortDirection()
        XCTAssertTrue(viewModel.sortDirectionAscending)

        viewModel.toggleSortDirection()
        XCTAssertFalse(viewModel.sortDirectionAscending)
    }

    func testSortWithSearchFilter() async throws {
        try await createMockProject(name: "Alpha Test", tags: [], duration: 30)
        try await createMockProject(name: "Zulu Test", tags: [], duration: 30)
        try await createMockProject(name: "Beta", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .name
        viewModel.sortDirectionAscending = true
        viewModel.searchText = "Test"

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.count, 2)
        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["Alpha Test", "Zulu Test"])
    }

    func testSortWithTagFilter() async throws {
        try await createMockProject(name: "A", tags: ["work"], duration: 30)
        try await createMockProject(name: "B", tags: ["personal"], duration: 30)
        try await createMockProject(name: "C", tags: ["work"], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .name
        viewModel.sortDirectionAscending = true
        viewModel.selectedTagFilter = "work"

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.count, 2)
        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["A", "C"])
    }

    func testSortWithBothFilters() async throws {
        try await createMockProject(name: "Work A", tags: ["work"], duration: 30)
        try await createMockProject(name: "Personal", tags: ["personal"], duration: 30)
        try await createMockProject(name: "Work B", tags: ["work"], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .name
        viewModel.sortDirectionAscending = true
        viewModel.searchText = "Work"
        viewModel.selectedTagFilter = "work"

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.count, 2)
        XCTAssertEqual(viewModel.filteredProjects.map { $0.name }, ["Work A", "Work B"])
    }

    func testSortStabilityWithEqualValues() async throws {
        // Create projects with same duration
        try await createMockProject(name: "First", tags: [], duration: 60)
        try await createMockProject(name: "Second", tags: [], duration: 60)
        try await createMockProject(name: "Third", tags: [], duration: 60)

        let viewModel = AppNavigationViewModel(library: library)
        viewModel.sortOption = .duration
        viewModel.sortDirectionAscending = false

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.filteredProjects.count, 3)
        // All have same duration, so order should be stable
        XCTAssertEqual(viewModel.filteredProjects.map { $0.duration }, [60, 60, 60])
    }

    func testDefaultSortIsDateUpdatedDescending() async throws {
        try await createMockProject(name: "Project", tags: [], duration: 30)

        let viewModel = AppNavigationViewModel(library: library)
        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.sortOption, .dateUpdated)
        XCTAssertFalse(viewModel.sortDirectionAscending)
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
