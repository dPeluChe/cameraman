//
//  ProjectStoreTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-18.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class ProjectStoreTests: XCTestCase {
    var tempDirectory: URL!
    var sut: ProjectStore!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for tests
        let tempDir = FileManager.default.temporaryDirectory
        tempDirectory = tempDir.appendingPathComponent("EngineKitTests_\(UUID().uuidString)", isDirectory: true)

        sut = ProjectStore(baseDirectory: tempDirectory)
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)

        try await super.tearDown()
    }

    // MARK: - Project Creation Tests

    func testCreateProject_WithValidRecording_CreatesProject() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let testName = "Test Project"
        let testTags = ["demo", "test"]

        // When
        let projectId = try await sut.createProject(
            from: recordingResult,
            name: testName,
            tags: testTags
        )

        // Then
        let project = try await sut.loadProject(projectId: projectId)
        XCTAssertEqual(project.name, testName)
        XCTAssertEqual(project.tags, testTags)
        XCTAssertEqual(project.sources.screen.path, "sources/screen.mov")
        XCTAssertEqual(project.timeline.duration, 120.0)
    }

    func testCreateProject_WithoutOptionalParameters_CreatesProjectWithDefaults() async throws {
        // Given
        let recordingResult = createMockRecordingResult()

        // When
        let projectId = try await sut.createProject(
            from: recordingResult,
            name: nil,
            tags: nil
        )

        // Then
        let project = try await sut.loadProject(projectId: projectId)
        XCTAssertEqual(project.name, "Untitled Recording")
        XCTAssertEqual(project.tags, [])
    }

    // MARK: - Project Loading Tests

    func testLoadProject_WithValidId_LoadsProject() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let projectId = try await sut.createProject(from: recordingResult, name: "Test", tags: [])

        // When
        let project = try await sut.loadProject(projectId: projectId)

        // Then
        XCTAssertEqual(project.projectId, projectId)
        XCTAssertEqual(project.name, "Test")
    }

    func testLoadProject_WithInvalidId_ThrowsError() async throws {
        // Given
        let invalidId = ProjectId()

        // When/Then
        do {
            _ = try await sut.loadProject(projectId: invalidId)
            XCTFail("Expected projectNotFound error")
        } catch EngineKitError.projectNotFound(let id) {
            XCTAssertEqual(id, invalidId)
        }
    }

    func testProjectDirectoryURL_ReturnsExistingDirectory() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let projectId = try await sut.createProject(from: recordingResult, name: "Test", tags: [])

        // When
        let projectDirectory = try await sut.projectDirectoryURL(for: projectId)

        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectDirectory.path))
        XCTAssertEqual(projectDirectory.lastPathComponent, projectId.uuidString)
    }

    // MARK: - Project Update Tests

    func testSaveProject_UpdatesUpdatedAt() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let projectId = try await sut.createProject(from: recordingResult, name: "Test", tags: [])
        var project = try await sut.loadProject(projectId: projectId)
        let originalUpdatedAt = project.updatedAt

        // Wait a bit to ensure timestamp difference (needs to be at least 1 second for Date resolution)
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // When
        project.name = "Updated Name"
        try await sut.saveProject(project)

        // Then
        let updatedProject = try await sut.loadProject(projectId: projectId)
        XCTAssertNotEqual(updatedProject.updatedAt, originalUpdatedAt)
        XCTAssertEqual(updatedProject.name, "Updated Name")
    }

    func testRenameProject_UpdatesName() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let projectId = try await sut.createProject(from: recordingResult, name: "Old Name", tags: [])
        let newName = "New Name"

        // When
        try await sut.renameProject(projectId: projectId, to: newName)

        // Then
        let project = try await sut.loadProject(projectId: projectId)
        XCTAssertEqual(project.name, newName)
    }

    func testSetTags_ReplacesTags() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let projectId = try await sut.createProject(from: recordingResult, name: "Test", tags: ["tag1", "tag2"])
        let newTags = ["tag3", "tag4", "tag5"]

        // When
        try await sut.setTags(projectId: projectId, tags: newTags)

        // Then
        let project = try await sut.loadProject(projectId: projectId)
        XCTAssertEqual(project.tags, newTags)
    }

    // MARK: - Project Deletion Tests

    func testDeleteProject_RemovesProject() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let projectId = try await sut.createProject(from: recordingResult, name: "Test", tags: [])

        // When
        try await sut.deleteProject(projectId: projectId)

        // Then
        do {
            _ = try await sut.loadProject(projectId: projectId)
            XCTFail("Expected projectNotFound error")
        } catch EngineKitError.projectNotFound {
            // Expected
        }
    }

    // MARK: - Project Listing Tests

    func testListProjects_ReturnsAllProjects() async throws {
        // Given - create separate recording results for each project
        let recordingResult1 = createMockRecordingResult()
        let recordingResult2 = createMockRecordingResult()

        let projectId1 = try await sut.createProject(from: recordingResult1, name: "Project 1", tags: ["tag1"])
        let projectId2 = try await sut.createProject(from: recordingResult2, name: "Project 2", tags: ["tag2"])

        // When
        let projects = try await sut.listProjects()

        // Then
        XCTAssertEqual(projects.count, 2)
        XCTAssertTrue(projects.contains { $0.projectId == projectId1 })
        XCTAssertTrue(projects.contains { $0.projectId == projectId2 })
    }

    func testListProjects_SortsByUpdatedAtNewestFirst() async throws {
        // Given - create separate recording results for each project
        let recordingResult1 = createMockRecordingResult()
        let recordingResult2 = createMockRecordingResult()

        // Create projects sequentially
        let projectId1 = try await sut.createProject(from: recordingResult1, name: "First", tags: [])
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds to ensure time difference

        let projectId2 = try await sut.createProject(from: recordingResult2, name: "Second", tags: [])

        // When
        let projects = try await sut.listProjects()

        // Then
        XCTAssertEqual(projects.count, 2)

        // Verify sorting - projects should be sorted by updatedAt (newest first)
        // projectId2 should come first since it was created later
        XCTAssertTrue(projects[0].updatedAt > projects[1].updatedAt)

        // Also verify the project IDs match our expectations
        let projectIds = projects.map { $0.projectId }
        XCTAssertTrue(projectIds.contains(projectId1))
        XCTAssertTrue(projectIds.contains(projectId2))
    }

    // MARK: - Schema Migration Tests

    func testLoadProject_WithOldSchemaVersion_AutoMigrates() async throws {
        // Given
        let recordingResult = createMockRecordingResult()
        let projectId = try await sut.createProject(from: recordingResult, name: "Test", tags: [])

        // Manually create an old schema version
        var project = try await sut.loadProject(projectId: projectId)
        project.schemaVersion = 0

        // When
        try await sut.saveProject(project)
        let loadedProject = try await sut.loadProject(projectId: projectId)

        // Then
        XCTAssertEqual(loadedProject.schemaVersion, 1) // Should be migrated to current
    }

    // MARK: - Helper Methods

    private func createMockRecordingResult() -> RecordingResult {
        // Create temporary files for testing within the test's temp directory
        let screenPath = tempDirectory.appendingPathComponent("test_screen_\(UUID().uuidString).mov")
        let telemetryPath = tempDirectory.appendingPathComponent("test_telemetry_\(UUID().uuidString).jsonl")

        // Create empty files
        FileManager.default.createFile(atPath: screenPath.path, contents: Data())
        FileManager.default.createFile(atPath: telemetryPath.path, contents: Data())

        return RecordingResult(
            screenPath: screenPath,
            cameraPath: nil,
            systemAudioPath: nil,
            micAudioPath: nil,
            telemetryPath: telemetryPath,
            duration: 120.0,
            startTime: Date(),
            endTime: Date().addingTimeInterval(120.0)
        )
    }
}
