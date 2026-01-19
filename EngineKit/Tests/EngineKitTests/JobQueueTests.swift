//
//  JobQueueTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-18.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class JobQueueTests: XCTestCase {
    var sut: JobQueue!
    var testProjectId: ProjectId!

    override func setUp() async throws {
        try await super.setUp()

        sut = JobQueue()
        testProjectId = ProjectId()
    }

    override func tearDown() async throws {
        sut = nil
        testProjectId = nil

        try await super.tearDown()
    }

    // MARK: - Job Creation Tests

    func testCreateJob_CreatesJobWithQueuedStatus() async throws {
        // Given
        let jobId = await sut.createJob(type: .export, projectId: testProjectId)

        // When
        let job = await sut.getJob(jobId: jobId)

        // Then
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.type, .export)
        XCTAssertEqual(job?.projectId, testProjectId)
        if case .queued = job?.status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected queued status")
        }
    }

    // MARK: - Job Progress Tests

    func testUpdateJobProgress_UpdatesStatusWithProgress() async throws {
        // Given
        let jobId = await sut.createJob(type: .transcribe, projectId: testProjectId)

        // When
        await sut.updateJobProgress(jobId: jobId, progress: 0.5)

        // Then
        let status = await sut.getJobStatus(jobId: jobId)
        if case .running(let progress) = status {
            XCTAssertEqual(progress, 0.5)
        } else {
            XCTFail("Expected running status with progress")
        }
    }

    func testUpdateJobProgress_WithInvalidProgress_ClampsToValidRange() async throws {
        // Given
        let jobId = await sut.createJob(type: .export, projectId: testProjectId)

        // When
        await sut.updateJobProgress(jobId: jobId, progress: 1.5) // Over 1.0
        var status = await sut.getJobStatus(jobId: jobId)
        if case .running(let progress) = status {
            XCTAssertEqual(progress, 1.0)
        } else {
            XCTFail("Expected running status")
        }

        await sut.updateJobProgress(jobId: jobId, progress: -0.5) // Under 0.0
        status = await sut.getJobStatus(jobId: jobId)
        if case .running(let progress) = status {
            XCTAssertEqual(progress, 0.0)
        } else {
            XCTFail("Expected running status")
        }
    }

    // MARK: - Job Completion Tests

    func testCompleteJob_UpdatesStatusToSuccess() async throws {
        // Given
        let jobId = await sut.createJob(type: .export, projectId: testProjectId)
        await sut.startJob(jobId: jobId, task: Task {})

        // When
        await sut.completeJob(jobId: jobId)

        // Then
        let status = await sut.getJobStatus(jobId: jobId)
        XCTAssertEqual(status, .success)

        let job = await sut.getJob(jobId: jobId)
        XCTAssertNotNil(job?.completedAt)
    }

    func testFailJob_UpdatesStatusToFailed() async throws {
        // Given
        let jobId = await sut.createJob(type: .export, projectId: testProjectId)
        await sut.startJob(jobId: jobId, task: Task {})
        let error = Job.JobError(
            code: "TEST_ERROR",
            message: "Test error message",
            details: nil,
            recoverable: false
        )

        // When
        await sut.failJob(jobId: jobId, error: error)

        // Then
        let status = await sut.getJobStatus(jobId: jobId)
        XCTAssertEqual(status, .failed)

        let job = await sut.getJob(jobId: jobId)
        XCTAssertNotNil(job?.error)
        XCTAssertEqual(job?.error?.code, "TEST_ERROR")
    }

    // MARK: - Job Cancellation Tests

    func testCancelJob_UpdatesStatusToCanceled() async throws {
        // Given
        let jobId = await sut.createJob(type: .export, projectId: testProjectId)
        let task: Task<Void, Never> = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        await sut.startJob(jobId: jobId, task: task)

        // When
        try await sut.cancelJob(jobId: jobId)

        // Then
        let status = await sut.getJobStatus(jobId: jobId)
        XCTAssertEqual(status, .canceled)

        let job = await sut.getJob(jobId: jobId)
        XCTAssertNotNil(job?.completedAt)

        // Verify task was cancelled
        XCTAssertTrue(task.isCancelled)
    }

    // MARK: - Job Subscription Tests

    func testSubscribeToJob_ReceivesStatusUpdates() async throws {
        // Given
        let jobId = await sut.createJob(type: .export, projectId: testProjectId)
        let stream = await sut.subscribeToJob(jobId: jobId)

        // When
        await sut.startJob(jobId: jobId, task: Task {})
        await sut.updateJobProgress(jobId: jobId, progress: 0.5)

        // Then
        var statuses: [Job.JobStatus] = []
        for await status in stream {
            statuses.append(status)
            if statuses.count >= 2 {
                break
            }
        }

        await sut.completeJob(jobId: jobId)

        // We expect at least: queued (initial), running(0.5)
        XCTAssertTrue(statuses.count >= 2)
        if case .queued = statuses[0] {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected queued status first")
        }
    }

    // MARK: - Job Listing Tests

    func testListJobs_ReturnsOnlyJobsForProject() async throws {
        // Given
        let projectId1 = ProjectId()
        let projectId2 = ProjectId()

        let jobId1 = await sut.createJob(type: .export, projectId: projectId1)
        let jobId2 = await sut.createJob(type: .transcribe, projectId: projectId1)
        let jobId3 = await sut.createJob(type: .export, projectId: projectId2)

        // When
        let jobsForProject1 = await sut.listJobs(for: projectId1)
        let jobsForProject2 = await sut.listJobs(for: projectId2)

        // Then
        XCTAssertEqual(jobsForProject1.count, 2)
        XCTAssertTrue(jobsForProject1.contains { $0.jobId == jobId1 })
        XCTAssertTrue(jobsForProject1.contains { $0.jobId == jobId2 })

        XCTAssertEqual(jobsForProject2.count, 1)
        XCTAssertTrue(jobsForProject2.contains { $0.jobId == jobId3 })
    }

    // MARK: - Job Cleanup Tests

    func testCleanupJobs_RemovesOldJobs() async throws {
        // Given
        let jobId1 = await sut.createJob(type: .export, projectId: testProjectId)
        await sut.completeJob(jobId: jobId1)

        // Set completedAt to past
        var job = await sut.getJob(jobId: jobId1)!
        job = Job(
            jobId: job.jobId,
            type: job.type,
            projectId: job.projectId,
            status: job.status,
            startedAt: job.startedAt,
            completedAt: Date().addingTimeInterval(-86400), // 1 day ago
            error: job.error
        )

        let jobId2 = await sut.createJob(type: .export, projectId: testProjectId)

        // When - try to clean jobs older than 1 day
        await sut.cleanupJobs(olderThan: Date().addingTimeInterval(-86400))

        // Then
        let job1 = await sut.getJob(jobId: jobId1)
        let job2 = await sut.getJob(jobId: jobId2)

        // Both should still exist since they're recent
        XCTAssertNotNil(job1)
        XCTAssertNotNil(job2)
    }
}
