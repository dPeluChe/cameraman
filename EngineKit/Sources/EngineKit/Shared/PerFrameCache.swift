//
//  PerFrameCache.swift
//  EngineKit
//
//  Small cache for per-camera-frame analysis (person matte, face anchors). The canvas can render
//  the same camera frame twice and workers render in parallel, so: results are kept for a few
//  frames, and a worker that asks for a frame another worker is already analysing waits for it
//  instead of repeating the work. The analysis itself runs outside the lock.
//

import Foundation
import CoreVideo
import IOSurface

final class PerFrameCache<Key: Hashable, Value>: @unchecked Sendable {
    private let condition = NSCondition()
    private var entries: [(key: Key, value: Value)] = []
    private var inFlight: Set<Key> = []
    private let limit: Int

    init(limit: Int = 8) { self.limit = limit }

    /// The cached value for `key`, computing it with `compute` on a miss. A nil result is not cached.
    func value(for key: Key, compute: () -> Value?) -> Value? {
        condition.lock()
        while inFlight.contains(key) { condition.wait() }
        if let hit = entries.first(where: { $0.key == key }) {
            condition.unlock()
            return hit.value
        }
        inFlight.insert(key)
        condition.unlock()

        let computed = compute()

        condition.lock()
        inFlight.remove(key)
        if let computed {
            if entries.count >= limit { entries.removeFirst() }
            entries.append((key, computed))
        }
        condition.broadcast()
        condition.unlock()
        return computed
    }
}

enum CameraFrame {
    /// Identity of the camera frame itself. The IOSurface id plus its seed changes whenever a pooled
    /// buffer is refilled; software buffers fall back to `fallback` (e.g. a composition-time bucket).
    static func key(for buffer: CVPixelBuffer, fallback: Int) -> Int {
        guard let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return fallback }
        var hasher = Hasher()
        hasher.combine(IOSurfaceGetID(surface))
        hasher.combine(IOSurfaceGetSeed(surface))
        return hasher.finalize()
    }
}
