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

    private let lock = NSLock()
    private var cache: [(key: Int, quality: Quality, mask: CIImage)] = []
    private static let cacheLimit = 8

    /// Matte scaled to the frame, white where the person is. `frameKey` identifies the camera frame
    /// (any value that is equal for repeated requests of the same frame). Nil if Vision fails.
    func mask(for buffer: CVPixelBuffer, frameKey: Int, quality: Quality) -> CIImage? {
        // One Vision request at a time: the handler is stateful and the compositor may render in parallel.
        lock.lock()
        defer { lock.unlock() }

        if let hit = cache.first(where: { $0.key == frameKey && $0.quality == quality }) { return hit.mask }

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
        // A touch of blur softens the stair-stepped edge without eating into hair.
        let scaled = raw
            .transformed(by: CGAffineTransform(scaleX: frame.width / raw.extent.width, y: frame.height / raw.extent.height))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 1.2)
            .cropped(to: frame)

        if cache.count >= Self.cacheLimit { cache.removeFirst() }
        cache.append((frameKey, quality, scaled))
        return scaled
    }
}
