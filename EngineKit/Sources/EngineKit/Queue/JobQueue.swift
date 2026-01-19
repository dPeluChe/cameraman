//
//  JobQueue.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

/// JobQueue manages async operations with progress tracking and cancellation
public actor JobQueue {
    /// Active jobs storage
    private var jobs: [JobId: Job] = [:]
    /// Job subscribers for progress updates
    private var subscribers: [JobId: AsyncStream<Job.JobStatus>.Continuation] = [:]
    /// Active task storage
    private var tasks: [JobId: Task<Void, Never>] = [:]

    /// Get the current status of a job
    /// - Parameter jobId: Job ID to query
    /// - Returns: Current JobStatus
    public func getJobStatus(jobId: JobId) -> Job.JobStatus? {
        return jobs[jobId]?.status
    }

    /// Get a job by ID
    /// - Parameter jobId: Job ID to query
    /// - Returns: Job if it exists
    public func getJob(jobId: JobId) -> Job? {
        return jobs[jobId]
    }

    /// Cancel a job
    /// - Parameter jobId: Job ID to cancel
    /// - Throws: If job cannot be canceled
    public func cancelJob(jobId: JobId) async throws {
        guard jobs[jobId] != nil else {
            throw EngineKitError.invalidConfiguration("Job not found: \(jobId.uuidString)")
        }

        // Cancel the underlying task
        tasks[jobId]?.cancel()

        // Update job status
        jobs[jobId]?.status = .canceled
        jobs[jobId]?.completedAt = Date()

        // Notify subscribers
        subscribers[jobId]?.yield(.canceled)
        subscribers[jobId]?.finish()
        subscribers.removeValue(forKey: jobId)
    }

    /// Subscribe to job status updates
    /// - Parameter jobId: Job ID to subscribe to
    /// - Returns: AsyncStream of JobStatus updates
    public func subscribeToJob(jobId: JobId) -> AsyncStream<Job.JobStatus> {
        return AsyncStream { continuation in
            subscribers[jobId] = continuation

            // Send current status immediately
            if let currentStatus = jobs[jobId]?.status {
                continuation.yield(currentStatus)
            }

            // Auto-finish when job completes
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.removeSubscriber(for: jobId)
                }
            }
        }
    }

    /// Remove a subscriber for a job
    private func removeSubscriber(for jobId: JobId) {
        subscribers.removeValue(forKey: jobId)
    }

    /// List all jobs for a project
    /// - Parameter projectId: Project ID to filter by
    /// - Returns: Array of jobs for the project
    public func listJobs(for projectId: ProjectId) -> [Job] {
        return jobs.values.filter { $0.projectId == projectId }
    }

    // MARK: - Internal Methods

    /// Create a new job
    /// - Parameters:
    ///   - type: Job type
    ///   - projectId: Associated project
    /// - Returns: Created JobId
    func createJob(type: Job.JobType, projectId: ProjectId) -> JobId {
        let jobId = JobId()
        let now = Date()

        let job = Job(
            jobId: jobId,
            type: type,
            projectId: projectId,
            status: .queued,
            startedAt: now,
            completedAt: nil,
            error: nil
        )

        jobs[jobId] = job
        return jobId
    }

    /// Start a job's execution
    /// - Parameters:
    ///   - jobId: Job to start
    ///   - task: Async task to execute
    func startJob(jobId: JobId, task: Task<Void, Never>) {
        tasks[jobId] = task
        updateJobStatus(jobId: jobId, status: .running(progress: 0))
    }

    /// Update job progress
    /// - Parameters:
    ///   - jobId: Job to update
    ///   - progress: Progress value (0.0 to 1.0)
    func updateJobProgress(jobId: JobId, progress: Double) {
        // Clamp progress to valid range [0, 1]
        let clampedProgress = max(0, min(1, progress))
        updateJobStatus(jobId: jobId, status: .running(progress: clampedProgress))
    }

    /// Mark job as completed successfully
    /// - Parameter jobId: Job to complete
    func completeJob(jobId: JobId) {
        jobs[jobId]?.status = .success
        jobs[jobId]?.completedAt = Date()
        subscribers[jobId]?.yield(.success)
        subscribers[jobId]?.finish()
        subscribers.removeValue(forKey: jobId)
        tasks.removeValue(forKey: jobId)
    }

    /// Mark job as failed
    /// - Parameters:
    ///   - jobId: Job that failed
    ///   - error: Error information
    func failJob(jobId: JobId, error: Job.JobError) {
        jobs[jobId]?.status = .failed
        jobs[jobId]?.error = error
        jobs[jobId]?.completedAt = Date()
        subscribers[jobId]?.yield(.failed)
        subscribers[jobId]?.finish()
        subscribers.removeValue(forKey: jobId)
        tasks.removeValue(forKey: jobId)
    }

    /// Update job status and notify subscribers
    private func updateJobStatus(jobId: JobId, status: Job.JobStatus) {
        jobs[jobId]?.status = status
        subscribers[jobId]?.yield(status)
    }

    /// Clean up old jobs (optional maintenance)
    /// - Parameter olderThan: Remove jobs completed before this date
    func cleanupJobs(olderThan date: Date) {
        let toRemove = jobs.values.filter { job in
            guard let completedAt = job.completedAt else { return false }
            return completedAt < date
        }.map { $0.jobId }

        for jobId in toRemove {
            jobs.removeValue(forKey: jobId)
            tasks.removeValue(forKey: jobId)
        }
    }
}
