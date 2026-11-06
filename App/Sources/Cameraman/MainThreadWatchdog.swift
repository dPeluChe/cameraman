//
//  MainThreadWatchdog.swift
//  App
//
//  Debug only: logs when the main thread stops answering, to tell a UI hang from a player stall.
//

import Foundation
import EngineKit

#if DEBUG
enum MainThreadWatchdog {
    private static let tick: TimeInterval = 0.1

    static func start() {
        var last = CFAbsoluteTimeGetCurrent()
        Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { _ in
            let now = CFAbsoluteTimeGetCurrent()
            if now - last > 0.3 { LogInfo(.ui, "[WATCHDOG] main thread blocked \(Int((now - last) * 1000)) ms") }
            last = now
        }
    }
}
#endif
