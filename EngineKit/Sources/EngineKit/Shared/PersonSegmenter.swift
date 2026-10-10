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

    private struct Key: Hashable {
        let frame: Int
        let accurate: Bool
    }

    private let cache = PerFrameCache<Key, CIImage>()

    /// Matte scaled to the frame, white where the person is. Nil if Vision fails.
    func mask(for buffer: CVPixelBuffer, frameKey: Int, quality: Quality) -> CIImage? {
        cache.value(for: Key(frame: frameKey, accurate: quality == .accurate)) {
            Self.segment(buffer, quality: quality)
        }
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
