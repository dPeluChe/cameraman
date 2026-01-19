//
//  ProjectLibraryTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class ProjectLibraryTests: XCTestCase {
    var tempDirectory: URL!
    var store: ProjectStore!
    var library: ProjectLibrary!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for tests
        let tempDir = FileManager.default.temporaryDirectory
        tempDirectory = tempDir.appendingPathComponent("ProjectLibraryTests_\(UUID().uuidString)", isDirectory: true)

        store = ProjectStore(baseDirectory: tempDirectory)
        library = ProjectLibrary(store: store)
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)

        try await super.tearDown()
    }

    // MARK: - Helper Methods

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

    private func createMultipleProjects(count: Int) async throws -> [ProjectId] {
        var projectIds: [ProjectId] = []

        for i in 0..<count {
            let name = "Project \(i)"
            let tags = ["tag\(i % 3)", "common"] // Rotate through tag0, tag1, tag2, plus "common"
            let duration = TimeInterval(60 + i * 30) // 60, 90, 120, 150...
            let projectId = try await createMockProject(name: name, tags: tags, duration: duration)
            projectIds.append(projectId)

            // Add a small delay to ensure different timestamps
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }

        return projectIds
    }

    // MARK: - Basic List Projects Tests

    func testListProjects_WithNoProjects_ReturnsEmpty() async throws {
        // When
        let projects = try await library.listProjects()

        // Then
        XCTAssertEqual(projects.count, 0)
    }

    func testListProjects_WithMultipleProjects_ReturnsAll() async throws {
        // Given
        let count = 5
        _ = try await createMultipleProjects(count: count)

        // When
        let projects = try await library.listProjects()

        // Then
        XCTAssertEqual(projects.count, count)
    }

    // MARK: - Sorting Tests

    func testListProjects_SortedByNameAscending() async throws {
        // Given
        _ = try await createMockProject(name: "Zebra", tags: [], duration: 60)
        _ = try await createMockProject(name: "Apple", tags: [], duration: 60)
        _ = try await createMockProject(name: "Middle", tags: [], duration: 60)

        // When
        let projects = try await library.listProjects(sort: .nameAscending)

        // Then
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].name, "Apple")
        XCTAssertEqual(projects[1].name, "Middle")
        XCTAssertEqual(projects[2].name, "Zebra")
    }

    func testListProjects_SortedByNameDescending() async throws {
        // Given
        _ = try await createMockProject(name: "Zebra", tags: [], duration: 60)
        _ = try await createMockProject(name: "Apple", tags: [], duration: 60)
        _ = try await createMockProject(name: "Middle", tags: [], duration: 60)

        // When
        let projects = try await library.listProjects(sort: .nameDescending)

        // Then
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].name, "Zebra")
        XCTAssertEqual(projects[1].name, "Middle")
        XCTAssertEqual(projects[2].name, "Apple")
    }

    func testListProjects_SortedByCreatedAtDescending() async throws {
        // Given
        let projectId1 = try await createMockProject(name: "First", tags: [], duration: 60)
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        let projectId2 = try await createMockProject(name: "Second", tags: [], duration: 60)

        // When
        let projects = try await library.listProjects(sort: .createdAtDescending)

        // Then
        XCTAssertEqual(projects.count, 2)
        XCTAssertEqual(projects[0].projectId, projectId2)
        XCTAssertEqual(projects[1].projectId, projectId1)
    }

    func testListProjects_SortedByDurationAscending() async throws {
        // Given
        _ = try await createMockProject(name: "Short", tags: [], duration: 30)
        _ = try await createMockProject(name: "Long", tags: [], duration: 120)
        _ = try await createMockProject(name: "Medium", tags: [], duration: 60)

        // When
        let projects = try await library.listProjects(sort: .durationAscending)

        // Then
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].name, "Short")
        XCTAssertEqual(projects[1].name, "Medium")
        XCTAssertEqual(projects[2].name, "Long")
    }

    func testListProjects_SortedByDurationDescending() async throws {
        // Given
        _ = try await createMockProject(name: "Short", tags: [], duration: 30)
        _ = try await createMockProject(name: "Long", tags: [], duration: 120)
        _ = try await createMockProject(name: "Medium", tags: [], duration: 60)

        // When
        let projects = try await library.listProjects(sort: .durationDescending)

        // Then
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].name, "Long")
        XCTAssertEqual(projects[1].name, "Medium")
        XCTAssertEqual(projects[2].name, "Short")
    }

    func testListProjects_SortedByTagsAscending() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: ["zebra"], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["apple"], duration: 60)
        _ = try await createMockProject(name: "Project3", tags: ["middle"], duration: 60)

        // When
        let projects = try await library.listProjects(sort: .tagsAscending)

        // Then
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].tags, ["apple"])
        XCTAssertEqual(projects[1].tags, ["middle"])
        XCTAssertEqual(projects[2].tags, ["zebra"])
    }

    // MARK: - Search Text Tests

    func testListProjects_WithSearchText_FiltersByName() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Pie", tags: [], duration: 60)
        _ = try await createMockProject(name: "Banana Split", tags: [], duration: 60)
        _ = try await createMockProject(name: "Cherry Tart", tags: [], duration: 60)

        let filter = ProjectFilter(searchText: "apple")

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Apple Pie")
    }

    func testListProjects_WithSearchText_FiltersByTags() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: ["tutorial", "demo"], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["review"], duration: 60)
        _ = try await createMockProject(name: "Project3", tags: ["tutorial"], duration: 60)

        let filter = ProjectFilter(searchText: "tutorial")

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 2)
        XCTAssertTrue(projects.allSatisfy { $0.tags.contains("tutorial") })
    }

    func testListProjects_WithSearchText_CaseInsensitive() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Pie", tags: [], duration: 60)
        _ = try await createMockProject(name: "Banana Split", tags: [], duration: 60)

        let filter1 = ProjectFilter(searchText: "APPLE")
        let filter2 = ProjectFilter(searchText: "apple")
        let filter3 = ProjectFilter(searchText: "ApPlE")

        // When
        let projects1 = try await library.listProjects(filter: filter1)
        let projects2 = try await library.listProjects(filter: filter2)
        let projects3 = try await library.listProjects(filter: filter3)

        // Then
        XCTAssertEqual(projects1.count, 1)
        XCTAssertEqual(projects2.count, 1)
        XCTAssertEqual(projects3.count, 1)
        XCTAssertEqual(projects1[0].name, "Apple Pie")
        XCTAssertEqual(projects2[0].name, "Apple Pie")
        XCTAssertEqual(projects3[0].name, "Apple Pie")
    }

    func testListProjects_WithMultipleSearchTerms_AllMustMatch() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Pie Recipe", tags: ["tutorial"], duration: 60)
        _ = try await createMockProject(name: "Apple Pie", tags: [], duration: 60)
        _ = try await createMockProject(name: "Recipe Book", tags: [], duration: 60)

        let filter = ProjectFilter(searchText: "apple recipe")

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Apple Pie Recipe")
    }

    // MARK: - Tag Filtering Tests

    func testListProjects_WithTagFilter_AllMode() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: ["tutorial", "demo"], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["tutorial"], duration: 60)
        _ = try await createMockProject(name: "Project3", tags: ["demo"], duration: 60)

        let filter = ProjectFilter(tags: ["tutorial", "demo"], tagMatchMode: .all)

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Project1")
    }

    func testListProjects_WithTagFilter_AnyMode() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: ["tutorial", "demo"], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["tutorial"], duration: 60)
        _ = try await createMockProject(name: "Project3", tags: ["demo"], duration: 60)
        _ = try await createMockProject(name: "Project4", tags: ["review"], duration: 60)

        let filter = ProjectFilter(tags: ["tutorial", "demo"], tagMatchMode: .any)

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 3)
        XCTAssertTrue(projects.allSatisfy { project in
            project.tags.contains("tutorial") || project.tags.contains("demo")
        })
    }

    func testListProjects_WithExcludedTags() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: ["tutorial", "demo"], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["tutorial", "review"], duration: 60)
        _ = try await createMockProject(name: "Project3", tags: ["demo", "review"], duration: 60)

        let filter = ProjectFilter(excludedTags: ["review"])

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Project1")
    }

    // MARK: - Date Range Tests

    func testListProjects_WithDateRange_FiltersCorrectly() async throws {
        // Given
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400) // -1 day
        let tomorrow = now.addingTimeInterval(86400) // +1 day

        _ = try await createMockProject(name: "Project1", tags: [], duration: 60)
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        let middleTime = Date()
        _ = try await createMockProject(name: "Project2", tags: [], duration: 60)
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        _ = try await createMockProject(name: "Project3", tags: [], duration: 60)

        // When - filter for projects created between yesterday and tomorrow
        let dateRange = ProjectFilter.DateRange(startDate: yesterday, endDate: tomorrow)
        let filter = ProjectFilter(dateRange: dateRange)

        let projects = try await library.listProjects(filter: filter)

        // Then - should return all 3 projects
        XCTAssertEqual(projects.count, 3)
    }

    func testListProjects_WithDateRange_ExcludesOldProjects() async throws {
        // Given
        let now = Date()
        let oneSecondAgo = now.addingTimeInterval(-1)

        _ = try await createMockProject(name: "Old Project", tags: [], duration: 60)
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        _ = try await createMockProject(name: "New Project", tags: [], duration: 60)

        // When - filter for projects created in the last second
        let dateRange = ProjectFilter.DateRange(startDate: oneSecondAgo, endDate: nil)
        let filter = ProjectFilter(dateRange: dateRange)

        let projects = try await library.listProjects(filter: filter)

        // Then - should only return the new project
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "New Project")
    }

    // MARK: - Duration Range Tests

    func testListProjects_WithDurationRange_FiltersCorrectly() async throws {
        // Given
        _ = try await createMockProject(name: "Short", tags: [], duration: 30)
        _ = try await createMockProject(name: "Medium", tags: [], duration: 60)
        _ = try await createMockProject(name: "Long", tags: [], duration: 120)

        let durationRange = ProjectFilter.DurationRange(minDuration: 45, maxDuration: 90)
        let filter = ProjectFilter(durationRange: durationRange)

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Medium")
    }

    func testListProjects_WithDurationRange_MinimumOnly() async throws {
        // Given
        _ = try await createMockProject(name: "Short", tags: [], duration: 30)
        _ = try await createMockProject(name: "Medium", tags: [], duration: 60)
        _ = try await createMockProject(name: "Long", tags: [], duration: 120)

        let durationRange = ProjectFilter.DurationRange(minDuration: 60, maxDuration: .infinity)
        let filter = ProjectFilter(durationRange: durationRange)

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 2)
        XCTAssertTrue(projects.allSatisfy { $0.duration >= 60 })
    }

    // MARK: - Pagination Tests

    func testListProjects_WithOffset_SkipsResults() async throws {
        // Given
        _ = try await createMultipleProjects(count: 10)

        // When
        let projects = try await library.listProjects(sort: .nameAscending, offset: 5)

        // Then
        XCTAssertEqual(projects.count, 5)
    }

    func testListProjects_WithLimit_LimitsResults() async throws {
        // Given
        _ = try await createMultipleProjects(count: 10)

        // When
        let projects = try await library.listProjects(sort: .nameAscending, limit: 5)

        // Then
        XCTAssertEqual(projects.count, 5)
    }

    func testListProjects_WithOffsetAndLimit_PaginatesCorrectly() async throws {
        // Given
        _ = try await createMultipleProjects(count: 10)

        // When
        let page1 = try await library.listProjects(sort: .nameAscending, offset: 0, limit: 3)
        let page2 = try await library.listProjects(sort: .nameAscending, offset: 3, limit: 3)
        let page3 = try await library.listProjects(sort: .nameAscending, offset: 6, limit: 3)
        let page4 = try await library.listProjects(sort: .nameAscending, offset: 9, limit: 3)

        // Then
        XCTAssertEqual(page1.count, 3)
        XCTAssertEqual(page2.count, 3)
        XCTAssertEqual(page3.count, 3)
        XCTAssertEqual(page4.count, 1)

        // Verify no overlap
        let page1Ids = Set(page1.map { $0.id })
        let page2Ids = Set(page2.map { $0.id })
        let page3Ids = Set(page3.map { $0.id })
        let page4Ids = Set(page4.map { $0.id })

        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))
        XCTAssertTrue(page2Ids.isDisjoint(with: page3Ids))
        XCTAssertTrue(page3Ids.isDisjoint(with: page4Ids))
    }

    func testListProjects_WithOffsetBeyondRange_ReturnsEmpty() async throws {
        // Given
        _ = try await createMultipleProjects(count: 5)

        // When
        let projects = try await library.listProjects(offset: 100)

        // Then
        XCTAssertEqual(projects.count, 0)
    }

    // MARK: - Count Projects Tests

    func testCountProjects_WithNoFilter_ReturnsTotalCount() async throws {
        // Given
        let count = 5
        _ = try await createMultipleProjects(count: count)

        // When
        let total = try await library.countProjects()

        // Then
        XCTAssertEqual(total, count)
    }

    func testCountProjects_WithFilter_ReturnsMatchingCount() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Tutorial", tags: ["tutorial"], duration: 60)
        _ = try await createMockProject(name: "Banana Review", tags: ["review"], duration: 60)
        _ = try await createMockProject(name: "Cherry Tutorial", tags: ["tutorial"], duration: 60)

        let filter = ProjectFilter(searchText: "tutorial")

        // When
        let count = try await library.countProjects(filter: filter)

        // Then
        XCTAssertEqual(count, 2)
    }

    func testCountProjects_IgnoresPagination() async throws {
        // Given
        _ = try await createMultipleProjects(count: 10)

        // When
        let count = try await library.countProjects()

        // Then
        XCTAssertEqual(count, 10)
    }

    // MARK: - Get All Tags Tests

    func testGetAllTags_ReturnsUniqueTags() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: ["tutorial", "demo"], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["tutorial", "review"], duration: 60)
        _ = try await createMockProject(name: "Project3", tags: ["demo", "review"], duration: 60)

        // When
        let tags = try await library.getAllTags()

        // Then
        XCTAssertEqual(tags.count, 3)
        XCTAssertTrue(tags.contains("tutorial"))
        XCTAssertTrue(tags.contains("demo"))
        XCTAssertTrue(tags.contains("review"))
    }

    func testGetAllTags_SortedAlphabetically() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: ["zebra", "apple"], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["middle", "apple"], duration: 60)

        // When
        let tags = try await library.getAllTags()

        // Then
        XCTAssertEqual(tags, ["apple", "middle", "zebra"])
    }

    func testGetAllTags_WithNoProjects_ReturnsEmpty() async throws {
        // When
        let tags = try await library.getAllTags()

        // Then
        XCTAssertEqual(tags.count, 0)
    }

    // MARK: - Search Projects Tests

    func testSearchProjects_WithEmptyText_ReturnsAllProjects() async throws {
        // Given
        _ = try await createMultipleProjects(count: 5)

        // When
        let projects = try await library.searchProjects(searchText: "")

        // Then
        XCTAssertEqual(projects.count, 5)
    }

    func testSearchProjects_ByNameOnly() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Tutorial", tags: ["demo"], duration: 60)
        _ = try await createMockProject(name: "Banana Review", tags: ["tutorial"], duration: 60)
        _ = try await createMockProject(name: "Cherry Tutorial", tags: ["demo"], duration: 60)

        // When
        let projects = try await library.searchProjects(
            searchText: "tutorial",
            searchFields: [.name]
        )

        // Then
        XCTAssertEqual(projects.count, 2)
        XCTAssertTrue(projects.allSatisfy { $0.name.contains("tutorial") })
    }

    func testSearchProjects_ByTagsOnly() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Tutorial", tags: ["demo"], duration: 60)
        _ = try await createMockProject(name: "Banana Review", tags: ["tutorial"], duration: 60)
        _ = try await createMockProject(name: "Cherry Tutorial", tags: ["demo"], duration: 60)

        // When
        let projects = try await library.searchProjects(
            searchText: "tutorial",
            searchFields: [.tags]
        )

        // Then
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Banana Review")
    }

    func testSearchProjects_ByNameAndTags() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Tutorial", tags: ["demo"], duration: 60)
        _ = try await createMockProject(name: "Tutorial Video", tags: ["tutorial"], duration: 60)
        _ = try await createMockProject(name: "Cherry Tutorial", tags: ["demo"], duration: 60)

        // When
        let projects = try await library.searchProjects(
            searchText: "tutorial",
            searchFields: [.name, .tags]
        )

        // Then
        XCTAssertEqual(projects.count, 3)
    }

    func testSearchProjects_WithMatchAllTerms_True() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Tutorial Video", tags: [], duration: 60)
        _ = try await createMockProject(name: "Apple Pie", tags: [], duration: 60)
        _ = try await createMockProject(name: "Tutorial Video", tags: [], duration: 60)

        // When
        let projects = try await library.searchProjects(
            searchText: "apple tutorial",
            matchAllTerms: true
        )

        // Then
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Apple Tutorial Video")
    }

    func testSearchProjects_WithMatchAllTerms_False() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Tutorial", tags: [], duration: 60)
        _ = try await createMockProject(name: "Banana Pie", tags: [], duration: 60)
        _ = try await createMockProject(name: "Cherry Video", tags: [], duration: 60)

        // When
        let projects = try await library.searchProjects(
            searchText: "apple banana",
            matchAllTerms: false
        )

        // Then
        XCTAssertEqual(projects.count, 2)
    }

    func testSearchProjects_WithCustomSort() async throws {
        // Given
        _ = try await createMockProject(name: "Zebra Tutorial", tags: [], duration: 30)
        _ = try await createMockProject(name: "Apple Tutorial", tags: [], duration: 120)
        _ = try await createMockProject(name: "Middle Tutorial", tags: [], duration: 60)

        // When
        let projects = try await library.searchProjects(
            searchText: "tutorial",
            sort: .durationAscending
        )

        // Then
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].name, "Zebra Tutorial")
        XCTAssertEqual(projects[1].name, "Middle Tutorial")
        XCTAssertEqual(projects[2].name, "Apple Tutorial")
    }

    // MARK: - Combined Filter Tests

    func testListProjects_WithCombinedFilters() async throws {
        // Given
        _ = try await createMockProject(name: "Apple Tutorial", tags: ["demo", "featured"], duration: 30)
        _ = try await createMockProject(name: "Apple Review", tags: ["tutorial"], duration: 90)
        _ = try await createMockProject(name: "Banana Tutorial", tags: ["demo"], duration: 60)
        _ = try await createMockProject(name: "Cherry Tutorial", tags: ["demo", "featured"], duration: 120)

        let filter = ProjectFilter(
            searchText: "tutorial",
            tags: ["demo"],
            tagMatchMode: .any,
            durationRange: ProjectFilter.DurationRange(minDuration: 45, maxDuration: .infinity)
        )

        // When
        let projects = try await library.listProjects(filter: filter, sort: .durationAscending)

        // Then
        XCTAssertEqual(projects.count, 2)
        XCTAssertEqual(projects[0].name, "Banana Tutorial")
        XCTAssertEqual(projects[1].name, "Cherry Tutorial")
    }

    // MARK: - Edge Cases Tests

    func testListProjects_WithSpecialCharactersInSearch() async throws {
        // Given
        _ = try await createMockProject(name: "Project (1)", tags: [], duration: 60)
        _ = try await createMockProject(name: "Project [2]", tags: [], duration: 60)
        _ = try await createMockProject(name: "Project {3}", tags: [], duration: 60)

        let filter1 = ProjectFilter(searchText: "(1)")
        let filter2 = ProjectFilter(searchText: "[2]")
        let filter3 = ProjectFilter(searchText: "{3}")

        // When
        let projects1 = try await library.listProjects(filter: filter1)
        let projects2 = try await library.listProjects(filter: filter2)
        let projects3 = try await library.listProjects(filter: filter3)

        // Then
        XCTAssertEqual(projects1.count, 1)
        XCTAssertEqual(projects2.count, 1)
        XCTAssertEqual(projects3.count, 1)
    }

    func testListProjects_WithUnicodeCharacters() async throws {
        // Given
        _ = try await createMockProject(name: "Tutorial español", tags: [], duration: 60)
        _ = try await createMockProject(name: "日本語チュートリアル", tags: [], duration: 60)
        _ = try await createMockProject(name: "中文教程", tags: [], duration: 60)

        let filter1 = ProjectFilter(searchText: "español")
        let filter2 = ProjectFilter(searchText: "日本語")
        let filter3 = ProjectFilter(searchText: "中文")

        // When
        let projects1 = try await library.listProjects(filter: filter1)
        let projects2 = try await library.listProjects(filter: filter2)
        let projects3 = try await library.listProjects(filter: filter3)

        // Then
        XCTAssertEqual(projects1.count, 1)
        XCTAssertEqual(projects2.count, 1)
        XCTAssertEqual(projects3.count, 1)
    }

    func testListProjects_WithEmptyTagsArray() async throws {
        // Given
        _ = try await createMockProject(name: "Project1", tags: [], duration: 60)
        _ = try await createMockProject(name: "Project2", tags: ["tutorial"], duration: 60)

        let filter = ProjectFilter(tags: [])

        // When
        let projects = try await library.listProjects(filter: filter)

        // Then
        XCTAssertEqual(projects.count, 2)
    }

    // MARK: - Performance Tests

    func testListProjects_PerformanceWithManyProjects() async throws {
        // Given
        let count = 100
        _ = try await createMultipleProjects(count: count)

        // When
        let start = Date()
        let projects = try await library.listProjects()
        let duration = Date().timeIntervalSince(start)

        // Then
        XCTAssertEqual(projects.count, count)
        // Should complete in reasonable time (< 1 second for 100 projects)
        XCTAssertLessThan(duration, 1.0)
    }

    func testSearchProjects_PerformanceWithComplexFilter() async throws {
        // Given
        let count = 50
        _ = try await createMultipleProjects(count: count)

        let filter = ProjectFilter(
            searchText: "project",
            tags: ["tag0", "tag1"],
            tagMatchMode: .any,
            durationRange: ProjectFilter.DurationRange(minDuration: 60, maxDuration: 150)
        )

        // When
        let start = Date()
        let projects = try await library.listProjects(filter: filter, sort: .nameAscending)
        let duration = Date().timeIntervalSince(start)

        // Then
        XCTAssertGreaterThan(projects.count, 0)
        // Should complete in reasonable time (< 1 second for 50 projects with complex filter)
        XCTAssertLessThan(duration, 1.0)
    }
}
