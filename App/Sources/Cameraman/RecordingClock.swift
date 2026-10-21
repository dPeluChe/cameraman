//
//  RecordingClock.swift
//  App
//

import Foundation

/// Wall clock for a recording that can pause: elapsed time skips the paused stretches.
struct RecordingClock {
    private var start: Date?
    private var paused: TimeInterval = 0
    private var pausedAt: Date?

    init(start: Date? = nil) { self.start = start }

    func elapsed(now: Date = Date()) -> TimeInterval {
        guard let start else { return 0 }
        let current = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(start) - paused - current)
    }

    mutating func pause(now: Date = Date()) { if pausedAt == nil { pausedAt = now } }

    mutating func resume(now: Date = Date()) {
        guard let at = pausedAt else { return }
        paused += now.timeIntervalSince(at)
        pausedAt = nil
    }
}
