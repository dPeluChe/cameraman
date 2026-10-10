//
//  PersonSegmenter.swift
//  EngineKit
//
//  On-device person matte for the camera layer (Vision). One matte per camera frame is kept so the
//  60 fps canvas does not segment the same 30 fps frame twice, and scrubbing back is cheap.
//

import Foundation
import CoreImage
import CoreVideo
import IOSurface
import Vision

final class PersonSegmenter: @unchecked Sendable {
    /// `.balanced` is about 20 ms per 1080p frame on an M1 Max (fits real time); `.accurate` is about
    /// 60 ms, used for export where only total time matters.
    enum Quality: Sendable {
        case balanced, accurate

        fileprivate var level: VNGeneratePersonSegmentationRequest.QualityLevel {
            self == .balanced ? .balanced : .accurate
        }
    }

    private struct Key: Hashable {
        let frame: Int
        let accurate: Bool
    }

    /// Guards the cache and the in-flight set only. Vision itself runs outside it: each call has its
    /// own request and handler, so parallel render workers segment different frames in parallel.
    private let condition = NSCondition()
    private var cache: [(key: Key, mask: CIImage)] = []
    private var inFlight: Set<Key> = []
    private static let cacheLimit = 8

    /// Identity of the camera frame itself. The IOSurface id plus its seed changes whenever a pooled
    /// buffer is refilled; software buffers fall back to `fallback` (e.g. a composition-time bucket).
    static func frameKey(for buffer: CVPixelBuffer, fallback: Int) -> Int {
        guard let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return fallback }
        var hasher = Hasher()
        hasher.combine(IOSurfaceGetID(surface))
        hasher.combine(IOSurfaceGetSeed(surface))
        return hasher.finalize()
    }

    /// Matte scaled to the frame, white where the person is. Nil if Vision fails.
    func mask(for buffer: CVPixelBuffer, frameKey: Int, quality: Quality) -> CIImage? {
        let key = Key(frame: frameKey, accurate: quality == .accurate)

        condition.lock()
        // Another worker is already segmenting this frame: wait for it instead of repeating the work.
        while inFlight.contains(key) { condition.wait() }
        if let hit = cache.first(where: { $0.key == key }) {
            condition.unlock()
            return hit.mask
        }
        inFlight.insert(key)
        condition.unlock()

        let mask = Self.segment(buffer, quality: quality)

        condition.lock()
        inFlight.remove(key)
        if let mask {
            if cache.count >= Self.cacheLimit { cache.removeFirst() }
            cache.append((key, mask))
        }
        condition.broadcast()
        condition.unlock()
        return mask
    }

    private static func segment(_ buffer: CVPixelBuffer, quality: Quality) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality.level
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let matte = request.results?.first?.pixelBuffer else { return nil }

        let frame = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let raw = CIImage(cvPixelBuffer: matte)
        // The matte comes back small; the bilinear upscale already softens the edge.
        return raw.transformed(by: CGAffineTransform(scaleX: frame.width / raw.extent.width, y: frame.height / raw.extent.height))
    }
}
