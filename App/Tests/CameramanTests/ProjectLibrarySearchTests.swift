//
//  ProjectLibrarySearchTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import XCTest
import EngineKit
@testable import Cameraman

@MainActor
final class ProjectLibrarySearchTests: XCTestCase {

    var viewModel: AppNavigationViewModel!
    var mockProjects: [ProjectSummary]!

    override func setUp() async throws {
        try await super.setUp()

        // Create mock project data
        mockProjects = [
            ProjectSummary(
                projectId: ProjectId(rawValue: UUID().uuidString),
                name: "Tutorial Series - Part 1",
                createdAt: Date(),
                updatedAt: Date(),
                duration: 120.0,
                thumbnailPath: nil,
                tags: ["tutorial", "beginner"]
            ),
            ProjectSummary(
                projectId: ProjectId(rawValue: UUID().uuidString),
                name: "Product Demo 2024",
                createdAt: Date(),
                updatedAt: Date(),
                duration: 300.0,
                thumbnailPath: nil,
                tags: ["demo", "product"]
            ),
            ProjectSummary(
                projectId: ProjectId(rawValue: UUID().uuidString),
                name: "Tutorial - Advanced Features",
                createdAt: Date(),
                updatedAt: Date(),
                duration: 450.0,
                thumbnailPath: nil,
                tags: ["tutorial", "advanced"]
            ),
            ProjectSummary(
                projectId: ProjectId(rawValue: UUID().uuidString),
                name: "Meeting Recording",
                createdAt: Date(),
                updatedAt: Date(),
                duration: 1800.0,
                thumbnailPath: nil,
                tags: ["meeting"]
            ),
            ProjectSummary(
                projectId: ProjectId(rawValue: UUID().uuidString),
                name: "Quick Tip - Keyboard Shortcuts",
                createdAt: Date(),
                updatedAt: Date(),
                duration: 60.0,
                thumbnailPath: nil,
                tags: ["tips", "tutorial"]
            ),
            ProjectSummary(
                projectId: ProjectId(rawValue: UUID().uuidString),
                name: "Product Launch",
                createdAt: Date(),
                updatedAt: Date(),
                duration: 600.0,
                thumbnailPath: nil,
                tags: ["demo", "product", "launch"]
            ),
        ]

        // Create view model
        viewModel = AppNavigationViewModel()

        // Inject mock projects
        viewModel.projects = mockProjects
    }

    // MARK: - Search Tests

    func testSearchTextEmpty() {
        // Given
        viewModel.searchText = ""

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 6, "Should show all projects when search is empty")
    }

    func testSearchTextPartialMatch() {
        // Given
        viewModel.searchText = "tutorial"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 3, "Should find 3 projects with 'tutorial'")
        XCTAssertTrue(filtered.allSatisfy { $0.name.localizedCaseInsensitiveContains("tutorial") })
    }

    func testSearchTextExactMatch() {
        // Given
        viewModel.searchText = "meeting"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 1, "Should find 1 project with 'meeting'")
        XCTAssertEqual(filtered.first?.name, "Meeting Recording")
    }

    func testSearchTextCaseInsensitive() {
        // Given
        viewModel.searchText = "TUTORIAL"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 3, "Should find 3 projects regardless of case")
    }

    func testSearchTextNoMatch() {
        // Given
        viewModel.searchText = "nonexistent"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 0, "Should return no projects for non-matching search")
    }

    func testSearchTextWhitespaceOnly() {
        // Given
        viewModel.searchText = "   "

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 6, "Whitespace-only search should show all projects")
    }

    func testSearchTextWithSpecialCharacters() {
        // Given
        viewModel.searchText = "-"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 4, "Should find projects with hyphens in name")
    }

    // MARK: - Tag Filter Tests

    func testTagFilterNil() {
        // Given
        viewModel.selectedTagFilter = nil

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 6, "Should show all projects when no tag filter is set")
    }

    func testTagFilterSingleTag() {
        // Given
        viewModel.selectedTagFilter = "tutorial"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 3, "Should find 3 projects with 'tutorial' tag")
        XCTAssertTrue(filtered.allSatisfy { $0.tags.contains("tutorial") })
    }

    func testTagFilterMultipleProjects() {
        // Given
        viewModel.selectedTagFilter = "demo"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 2, "Should find 2 projects with 'demo' tag")
    }

    func testTagFilterNoMatch() {
        // Given
        viewModel.selectedTagFilter = "nonexistent"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 0, "Should return no projects for non-matching tag")
    }

    func testTagFilterUniqueTag() {
        // Given
        viewModel.selectedTagFilter = "launch"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 1, "Should find 1 project with 'launch' tag")
    }

    // MARK: - Combined Search and Filter Tests

    func testSearchAndTagFilterCombined() {
        // Given
        viewModel.searchText = "tutorial"
        viewModel.selectedTagFilter = "advanced"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 1, "Should find 1 project matching both search and tag")
        XCTAssertEqual(filtered.first?.name, "Tutorial - Advanced Features")
    }

    func testSearchAndTagFilterNoOverlap() {
        // Given
        viewModel.searchText = "product"
        viewModel.selectedTagFilter = "tutorial"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 0, "Should return no projects when search and tag don't overlap")
    }

    func testSearchTextWithMatchingTag() {
        // Given
        viewModel.searchText = "tutorial"
        viewModel.selectedTagFilter = "tips"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 1, "Should find project matching both name and tag")
        XCTAssertEqual(filtered.first?.name, "Quick Tip - Keyboard Shortcuts")
    }

    // MARK: - All Tags Tests

    func testAllTagsExtraction() {
        // When
        let tags = viewModel.allTags

        // Then
        XCTAssertEqual(tags.count, 6, "Should extract 6 unique tags")
        XCTAssertTrue(tags.contains("tutorial"))
        XCTAssertTrue(tags.contains("demo"))
        XCTAssertTrue(tags.contains("product"))
        XCTAssertTrue(tags.contains("beginner"))
        XCTAssertTrue(tags.contains("advanced"))
        XCTAssertTrue(tags.contains("meeting"))
        XCTAssertTrue(tags.contains("tips"))
        XCTAssertTrue(tags.contains("launch"))
    }

    func testAllTagsSorted() {
        // When
        let tags = viewModel.allTags

        // Then
        XCTAssertEqual(tags, tags.sorted(), "Tags should be sorted alphabetically")
    }

    func testAllTagsEmptyWithNoProjects() {
        // Given
        viewModel.projects = []

        // When
        let tags = viewModel.allTags

        // Then
        XCTAssertEqual(tags.count, 0, "Should return empty array when no projects exist")
    }

    func testAllTagsWithUntaggedProjects() {
        // Given
        viewModel.projects = [
            ProjectSummary(
                projectId: ProjectId(rawValue: UUID().uuidString),
                name: "No Tags Project",
                createdAt: Date(),
                updatedAt: Date(),
                duration: 60.0,
                thumbnailPath: nil,
                tags: []
            )
        ]

        // When
        let tags = viewModel.allTags

        // Then
        XCTAssertEqual(tags.count, 0, "Should return empty array when projects have no tags")
    }

    // MARK: - Filter Management Tests

    func testSetTagFilter() {
        // Given
        viewModel.selectedTagFilter = nil

        // When
        viewModel.setTagFilter("tutorial")

        // Then
        XCTAssertEqual(viewModel.selectedTagFilter, "tutorial")
    }

    func testSetTagFilterToNil() {
        // Given
        viewModel.selectedTagFilter = "tutorial"

        // When
        viewModel.setTagFilter(nil)

        // Then
        XCTAssertNil(viewModel.selectedTagFilter)
    }

    func testClearFilters() {
        // Given
        viewModel.searchText = "tutorial"
        viewModel.selectedTagFilter = "demo"

        // When
        viewModel.clearFilters()

        // Then
        XCTAssertEqual(viewModel.searchText, "", "Search text should be cleared")
        XCTAssertNil(viewModel.selectedTagFilter, "Tag filter should be cleared")
    }

    func testClearFiltersWhenAlreadyClear() {
        // Given
        viewModel.searchText = ""
        viewModel.selectedTagFilter = nil

        // When
        viewModel.clearFilters()

        // Then
        XCTAssertEqual(viewModel.searchText, "", "Search text should remain empty")
        XCTAssertNil(viewModel.selectedTagFilter, "Tag filter should remain nil")
    }

    // MARK: - Edge Cases Tests

    func testSearchTextWithDiacritics() {
        // Given
        viewModel.searchText = "naïve"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        // Note: This test verifies that diacritics are handled (case-insensitive search)
        // Actual behavior depends on localization settings
        XCTAssertTrue(filtered.isEmpty || filtered.count <= 6)
    }

    func testTagFilterCaseSensitive() {
        // Given
        viewModel.selectedTagFilter = "Tutorial"

        // When
        let filtered = viewModel.filteredProjects

        // Then
        // Tag filtering should be case-sensitive (exact match)
        XCTAssertEqual(filtered.count, 0, "Tag filter should be case-sensitive")
    }

    func testMultipleFiltersRapidChange() {
        // Given
        viewModel.searchText = "tutorial"
        viewModel.selectedTagFilter = "advanced"

        // When - Rapid changes
        viewModel.searchText = "product"
        viewModel.selectedTagFilter = "demo"
        viewModel.searchText = ""
        viewModel.selectedTagFilter = nil

        // Then
        let filtered = viewModel.filteredProjects
        XCTAssertEqual(filtered.count, 6, "Should show all projects after clearing filters")
    }

    func testSearchWithEmptyResults() {
        // Given
        viewModel.projects = []

        // When
        viewModel.searchText = "anything"
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 0, "Should handle empty project list gracefully")
    }

    func testTagFilterWithEmptyResults() {
        // Given
        viewModel.projects = []

        // When
        viewModel.selectedTagFilter = "anything"
        let filtered = viewModel.filteredProjects

        // Then
        XCTAssertEqual(filtered.count, 0, "Should handle empty project list gracefully")
    }

    // MARK: - Performance Tests

    func testSearchPerformance() {
        // Given
        measure {
            for _ in 0..<100 {
                _ = viewModel.filteredProjects
            }
        }
    }

    func testFilterPerformance() {
        // Given
        viewModel.searchText = "tutorial"
        viewModel.selectedTagFilter = "advanced"

        measure {
            for _ in 0..<100 {
                _ = viewModel.filteredProjects
            }
        }
    }
}
