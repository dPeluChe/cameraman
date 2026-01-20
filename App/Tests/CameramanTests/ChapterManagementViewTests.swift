//
//  ChapterManagementViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-K, P2 Task 2: Automatic Chapters
//

import XCTest
@testable import Cameraman
import EngineKit

/// Tests for chapter management functionality
final class ChapterManagementViewTests: XCTestCase {

    // MARK: - Project.Chapter Model Tests

    func testChapterInitialization() {
        let chapter = Project.Chapter(
            title: "Introduction",
            startTime: 0.0,
            endTime: 30.0,
            summary: "Opening remarks",
            keywords: ["intro", "welcome"]
        )

        XCTAssertEqual(chapter.title, "Introduction")
        XCTAssertEqual(chapter.startTime, 0.0)
        XCTAssertEqual(chapter.endTime, 30.0)
        XCTAssertEqual(chapter.summary, "Opening remarks")
        XCTAssertEqual(chapter.keywords, ["intro", "welcome"])
        XCTAssertNotNil(chapter.id)
    }

    func testChapterDuration() {
        let chapter = Project.Chapter(
            title: "Test Chapter",
            startTime: 10.0,
            endTime: 40.0
        )

        XCTAssertEqual(chapter.duration, 30.0)
    }

    func testChapterWithOptionalFields() {
        let chapter = Project.Chapter(
            title: "Minimal Chapter",
            startTime: 0.0,
            endTime: 15.0
        )

        XCTAssertEqual(chapter.title, "Minimal Chapter")
        XCTAssertNil(chapter.summary)
        XCTAssertTrue(chapter.keywords.isEmpty)
        XCTAssertEqual(chapter.duration, 15.0)
    }

    func testChapterEquality() {
        let chapter1 = Project.Chapter(
            id: UUID(),
            title: "Same Title",
            startTime: 0.0,
            endTime: 30.0
        )

        let chapter2 = Project.Chapter(
            id: chapter1.id,
            title: "Same Title",
            startTime: 0.0,
            endTime: 30.0
        )

        XCTAssertEqual(chapter1, chapter2)
    }

    func testChapterInequality() {
        let chapter1 = Project.Chapter(
            title: "First",
            startTime: 0.0,
            endTime: 30.0
        )

        let chapter2 = Project.Chapter(
            title: "Second",
            startTime: 30.0,
            endTime: 60.0
        )

        XCTAssertNotEqual(chapter1, chapter2)
    }

    func testChapterCodable() {
        let chapter = Project.Chapter(
            title: "Encodable Chapter",
            startTime: 15.0,
            endTime: 45.0,
            summary: "Test encoding",
            keywords: ["test", "encoding"]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(chapter)
            let decoded = try decoder.decode(Project.Chapter.self, from: data)

            XCTAssertEqual(chapter.id, decoded.id)
            XCTAssertEqual(chapter.title, decoded.title)
            XCTAssertEqual(chapter.startTime, decoded.startTime)
            XCTAssertEqual(chapter.endTime, decoded.endTime)
            XCTAssertEqual(chapter.summary, decoded.summary)
            XCTAssertEqual(chapter.keywords, decoded.keywords)
        } catch {
            XCTFail("Encoding/decoding failed: \(error)")
        }
    }

    // MARK: - Project.Chapters Array Tests

    func testProjectWithChapters() {
        let chapters = [
            Project.Chapter(
                title: "Chapter 1",
                startTime: 0.0,
                endTime: 30.0
            ),
            Project.Chapter(
                title: "Chapter 2",
                startTime: 30.0,
                endTime: 60.0
            )
        ]

        var project = createMockProject()
        project.chapters = chapters

        XCTAssertEqual(project.chapters.count, 2)
        XCTAssertEqual(project.chapters.first?.title, "Chapter 1")
        XCTAssertEqual(project.chapters.last?.title, "Chapter 2")
    }

    func testProjectChaptersPersistence() {
        var project = createMockProject()
        project.chapters = [
            Project.Chapter(
                title: "Persistent Chapter",
                startTime: 0.0,
                endTime: 45.0
            )
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(project)
            let decoded = try decoder.decode(Project.self, from: data)

            XCTAssertEqual(decoded.chapters.count, 1)
            XCTAssertEqual(decoded.chapters.first?.title, "Persistent Chapter")
        } catch {
            XCTFail("Project encoding/decoding failed: \(error)")
        }
    }

    // MARK: - ProjectEditor Chapter Management Tests

    func testAddChapter() async {
        let editor = await ProjectEditor.mock()
        let initialCount = editor.project.chapters.count

        let chapter = Project.Chapter(
            title: "New Chapter",
            startTime: 0.0,
            endTime: 30.0
        )

        let success = await editor.addChapter(chapter)

        XCTAssertTrue(success)
        XCTAssertEqual(editor.project.chapters.count, initialCount + 1)
        XCTAssertTrue(editor.project.chapters.contains { $0.title == "New Chapter" })
    }

    func testAddChapterMaintainsChronologicalOrder() async {
        let editor = await ProjectEditor.mock()

        // Add chapters out of order
        let chapter2 = Project.Chapter(
            title: "Chapter 2",
            startTime: 30.0,
            endTime: 60.0
        )

        let chapter1 = Project.Chapter(
            title: "Chapter 1",
            startTime: 0.0,
            endTime: 30.0
        )

        _ = await editor.addChapter(chapter2)
        _ = await editor.addChapter(chapter1)

        // Verify chronological order
        XCTAssertEqual(editor.project.chapters.first?.title, "Chapter 1")
        XCTAssertEqual(editor.project.chapters.last?.title, "Chapter 2")
    }

    func testUpdateChapterTitle() async {
        let editor = await ProjectEditor.mock()

        let chapter = Project.Chapter(
            title: "Original Title",
            startTime: 0.0,
            endTime: 30.0
        )

        _ = await editor.addChapter(chapter)

        let success = await editor.updateChapter(
            chapterId: chapter.id,
            title: "Updated Title"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(
            editor.project.chapters.first { $0.id == chapter.id }?.title,
            "Updated Title"
        )
    }

    func testUpdateChapterSummary() async {
        let editor = await ProjectEditor.mock()

        let chapter = Project.Chapter(
            title: "Test",
            startTime: 0.0,
            endTime: 30.0
        )

        _ = await editor.addChapter(chapter)

        let success = await editor.updateChapter(
            chapterId: chapter.id,
            summary: "New summary"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(
            editor.project.chapters.first { $0.id == chapter.id }?.summary,
            "New summary"
        )
    }

    func testUpdateChapterKeywords() async {
        let editor = await ProjectEditor.mock()

        let chapter = Project.Chapter(
            title: "Test",
            startTime: 0.0,
            endTime: 30.0
        )

        _ = await editor.addChapter(chapter)

        let newKeywords = ["keyword1", "keyword2", "keyword3"]
        let success = await editor.updateChapter(
            chapterId: chapter.id,
            keywords: newKeywords
        )

        XCTAssertTrue(success)
        XCTAssertEqual(
            editor.project.chapters.first { $0.id == chapter.id }?.keywords,
            newKeywords
        )
    }

    func testUpdateMultipleChapterFields() async {
        let editor = await ProjectEditor.mock()

        let chapter = Project.Chapter(
            title: "Original",
            startTime: 0.0,
            endTime: 30.0
        )

        _ = await editor.addChapter(chapter)

        let success = await editor.updateChapter(
            chapterId: chapter.id,
            title: "Updated Title",
            summary: "Updated summary",
            keywords: ["updated"]
        )

        XCTAssertTrue(success)

        let updatedChapter = editor.project.chapters.first { $0.id == chapter.id }
        XCTAssertEqual(updatedChapter?.title, "Updated Title")
        XCTAssertEqual(updatedChapter?.summary, "Updated summary")
        XCTAssertEqual(updatedChapter?.keywords, ["updated"])
    }

    func testDeleteChapter() async {
        let editor = await ProjectEditor.mock()

        let chapter = Project.Chapter(
            title: "To Delete",
            startTime: 0.0,
            endTime: 30.0
        )

        _ = await editor.addChapter(chapter)
        let initialCount = editor.project.chapters.count

        let success = await editor.deleteChapter(chapterId: chapter.id)

        XCTAssertTrue(success)
        XCTAssertEqual(editor.project.chapters.count, initialCount - 1)
        XCTAssertFalse(editor.project.chapters.contains { $0.id == chapter.id })
    }

    func testDeleteNonExistentChapter() async {
        let editor = await ProjectEditor.mock()

        let success = await editor.deleteChapter(chapterId: UUID())

        XCTAssertFalse(success)
    }

    func testChapterUndoRedo() async {
        let editor = await ProjectEditor.mock()

        let chapter = Project.Chapter(
            title: "Undo Test",
            startTime: 0.0,
            endTime: 30.0
        )

        let initialCount = editor.project.chapters.count

        // Add chapter
        _ = await editor.addChapter(chapter)
        XCTAssertEqual(editor.project.chapters.count, initialCount + 1)

        // Undo
        _ = await editor.undo()
        XCTAssertEqual(editor.project.chapters.count, initialCount)

        // Redo
        _ = await editor.redo()
        XCTAssertEqual(editor.project.chapters.count, initialCount + 1)
    }

    // MARK: - AI Suggestion to Chapter Tests

    func testApplyChapterSuggestion() async {
        let editor = await ProjectEditor.mock()

        let suggestion = Suggestion(
            id: UUID(),
            type: .createChapter,
            title: "Suggested Chapter",
            description: "AI generated chapter",
            confidence: 0.95,
            timelineIn: 0.0,
            timelineOut: 30.0,
            metadata: [
                "title": "AI Generated Title",
                "summary": "AI generated summary",
                "keywords": ["ai", "chapter"]
            ]
        )

        let addedCount = await editor.applyChapterSuggestions(from: [suggestion])

        XCTAssertEqual(addedCount, 1)
        XCTAssertEqual(editor.project.chapters.count, 1)
        XCTAssertEqual(editor.project.chapters.first?.title, "AI Generated Title")
        XCTAssertEqual(editor.project.chapters.first?.summary, "AI generated summary")
        XCTAssertEqual(editor.project.chapters.first?.keywords, ["ai", "chapter"])
    }

    func testApplyMultipleChapterSuggestions() async {
        let editor = await ProjectEditor.mock()

        let suggestions = [
            Suggestion(
                id: UUID(),
                type: .createChapter,
                title: "Chapter 1",
                description: "First chapter",
                confidence: 0.9,
                timelineIn: 0.0,
                timelineOut: 30.0,
                metadata: ["title": "First Chapter"]
            ),
            Suggestion(
                id: UUID(),
                type: .createChapter,
                title: "Chapter 2",
                description: "Second chapter",
                confidence: 0.85,
                timelineIn: 30.0,
                timelineOut: 60.0,
                metadata: ["title": "Second Chapter"]
            )
        ]

        let addedCount = await editor.applyChapterSuggestions(from: suggestions)

        XCTAssertEqual(addedCount, 2)
        XCTAssertEqual(editor.project.chapters.count, 2)
    }

    func testApplyChapterSuggestionWithMissingMetadata() async {
        let editor = await ProjectEditor.mock()

        let suggestion = Suggestion(
            id: UUID(),
            type: .createChapter,
            title: "Minimal Suggestion",
            description: "No metadata",
            confidence: 0.8,
            timelineIn: 0.0,
            timelineOut: 30.0,
            metadata: [:]
        )

        let addedCount = await editor.applyChapterSuggestions(from: [suggestion])

        XCTAssertEqual(addedCount, 1)
        XCTAssertEqual(editor.project.chapters.count, 1)
        XCTAssertEqual(editor.project.chapters.first?.title, "Untitled Chapter")
        XCTAssertNil(editor.project.chapters.first?.summary)
        XCTAssertTrue(editor.project.chapters.first?.keywords.isEmpty)
    }

    func testApplyChapterSuggestionIgnoresNonChapterSuggestions() async {
        let editor = await ProjectEditor.mock()

        let suggestions = [
            Suggestion(
                id: UUID(),
                type: .removeSilence,
                title: "Silence",
                description: "Remove silence",
                confidence: 0.9,
                timelineIn: 0.0,
                timelineOut: 5.0,
                metadata: [:]
            ),
            Suggestion(
                id: UUID(),
                type: .createChapter,
                title: "Chapter",
                description: "Create chapter",
                confidence: 0.9,
                timelineIn: 5.0,
                timelineOut: 30.0,
                metadata: ["title": "Valid Chapter"]
            )
        ]

        let addedCount = await editor.applyChapterSuggestions(from: suggestions)

        // Should only add the chapter suggestion
        XCTAssertEqual(addedCount, 1)
        XCTAssertEqual(editor.project.chapters.count, 1)
        XCTAssertEqual(editor.project.chapters.first?.title, "Valid Chapter")
    }

    // MARK: - Integration Tests

    func testChapterGenerationToApplicationWorkflow() async {
        let editor = await ProjectEditor.mock()

        // Simulate AI-generated chapter suggestions
        let aiSuggestions = [
            Suggestion(
                id: UUID(),
                type: .createChapter,
                title: "Introduction",
                description: "Chapter 1",
                confidence: 0.95,
                timelineIn: 0.0,
                timelineOut: 30.0,
                metadata: [
                    "title": "Introduction",
                    "summary": "Opening remarks",
                    "keywords": ["intro", "welcome"]
                ]
            ),
            Suggestion(
                id: UUID(),
                type: .createChapter,
                title: "Main Content",
                description: "Chapter 2",
                confidence: 0.92,
                timelineIn: 30.0,
                timelineOut: 90.0,
                metadata: [
                    "title": "Main Content",
                    "summary": "Core material",
                    "keywords": ["content", "main"]
                ]
            )
        ]

        // Apply all suggestions
        let addedCount = await editor.applyChapterSuggestions(from: aiSuggestions)

        // Verify all chapters were added
        XCTAssertEqual(addedCount, 2)
        XCTAssertEqual(editor.project.chapters.count, 2)

        // Verify chronological order
        XCTAssertEqual(editor.project.chapters[0].title, "Introduction")
        XCTAssertEqual(editor.project.chapters[1].title, "Main Content")

        // Verify metadata was preserved
        XCTAssertEqual(editor.project.chapters[0].summary, "Opening remarks")
        XCTAssertEqual(editor.project.chapters[0].keywords, ["intro", "welcome"])
        XCTAssertEqual(editor.project.chapters[1].summary, "Core material")
        XCTAssertEqual(editor.project.chapters[1].keywords, ["content", "main"])
    }

    func testChapterEditingWorkflow() async {
        let editor = await ProjectEditor.mock()

        // Add initial chapter
        let chapter = Project.Chapter(
            title: "Original",
            startTime: 0.0,
            endTime: 30.0,
            summary: "Original summary",
            keywords: ["original"]
        )

        _ = await editor.addChapter(chapter)

        // Update chapter
        let success = await editor.updateChapter(
            chapterId: chapter.id,
            title: "Updated",
            summary: "Updated summary",
            keywords: ["updated", "modified"]
        )

        XCTAssertTrue(success)

        let updatedChapter = editor.project.chapters.first { $0.id == chapter.id }
        XCTAssertEqual(updatedChapter?.title, "Updated")
        XCTAssertEqual(updatedChapter?.summary, "Updated summary")
        XCTAssertEqual(updatedChapter?.keywords, ["updated", "modified"])

        // Verify undo works
        _ = await editor.undo()
        let undoneChapter = editor.project.chapters.first { $0.id == chapter.id }
        XCTAssertEqual(undoneChapter?.title, "Original")
        XCTAssertEqual(undoneChapter?.summary, "Original summary")
        XCTAssertEqual(undoneChapter?.keywords, ["original"])
    }

    // MARK: - Performance Tests

    func testChapterPerformanceWithManyChapters() async {
        let editor = await ProjectEditor.mock()

        // Add 100 chapters
        var chapters: [Project.Chapter] = []
        for i in 0..<100 {
            chapters.append(Project.Chapter(
                title: "Chapter \(i)",
                startTime: TimeInterval(i * 30),
                endTime: TimeInterval((i + 1) * 30)
            ))
        }

        let startTime = Date()
        for chapter in chapters {
            _ = await editor.addChapter(chapter)
        }
        let endTime = Date()

        XCTAssertEqual(editor.project.chapters.count, 100)
        let duration = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 5.0, "Adding 100 chapters should take less than 5 seconds")
    }

    // MARK: - Edge Cases Tests

    func testChapterWithZeroDuration() {
        let chapter = Project.Chapter(
            title: "Zero Duration",
            startTime: 30.0,
            endTime: 30.0
        )

        XCTAssertEqual(chapter.duration, 0.0)
    }

    func testChapterWithNegativeDuration() {
        // This represents an invalid chapter
        let chapter = Project.Chapter(
            title: "Negative Duration",
            startTime: 60.0,
            endTime: 30.0
        )

        // Duration should be negative, indicating an error condition
        XCTAssertLessThan(chapter.duration, 0.0)
    }

    func testChapterWithVeryLongTitle() {
        let longTitle = String(repeating: "A", count: 1000)
        let chapter = Project.Chapter(
            title: longTitle,
            startTime: 0.0,
            endTime: 30.0
        )

        XCTAssertEqual(chapter.title.count, 1000)
    }

    func testChapterWithManyKeywords() {
        let manyKeywords = Array(0...100).map { "keyword\($0)" }
        let chapter = Project.Chapter(
            title: "Many Keywords",
            startTime: 0.0,
            endTime: 30.0,
            keywords: manyKeywords
        )

        XCTAssertEqual(chapter.keywords.count, 101)
    }

    // MARK: - Helper Methods

    private func createMockProject() -> Project {
        Project(
            schemaVersion: 1,
            projectId: UUID(),
            name: "Test Project",
            tags: ["test"],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                )
            ),
            timeline: Project.Timeline(
                duration: 60.0,
                segments: []
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000"),
                layout: CanvasLayout.defaultLayout(for: .fullscreen)
            ),
            overlays: [],
            captions: nil,
            chapters: []
        )
    }
}
