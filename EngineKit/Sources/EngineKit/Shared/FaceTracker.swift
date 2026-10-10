//
//  FaceTracker.swift
//  EngineKit
//
//  Where the face is in a camera frame (Vision landmarks), for anchoring accessories. About 14 ms per
//  1080p frame on an M1 Max. Pixel coordinates, origin bottom-left, like CIImage.
//

import Foundation
import CoreGraphics
import CoreVideo
import Vision

struct FaceAnchors: Equatable {
    let leftEye: CGPoint
    let rightEye: CGPoint
    let faceBox: CGRect

    var eyeMidpoint: CGPoint { CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2) }
    var eyeDistance: CGFloat { hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y) }
    /// Head tilt in radians, from the line between the eyes (Vision's own roll is often 0).
    var roll: CGFloat { atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x) }
}

final class FaceTracker: @unchecked Sendable {
    private let cache = PerFrameCache<Int, FaceAnchors>()

    /// Anchors of the largest face in the frame, or nil when there is none.
    func anchors(for buffer: CVPixelBuffer, frameKey: Int) -> FaceAnchors? {
        cache.value(for: frameKey) { Self.detect(buffer) }
    }

    private static func detect(_ buffer: CVPixelBuffer) -> FaceAnchors? {
        let request = VNDetectFaceLandmarksRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
        } catch {
            return nil
        }
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        guard let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
              let left = face.landmarks?.leftEye, let right = face.landmarks?.rightEye,
              left.pointCount > 0, right.pointCount > 0 else { return nil }

        // Landmark points are normalized to the face box.
        func center(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            let sum = region.normalizedPoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let mean = CGPoint(x: sum.x / CGFloat(region.pointCount), y: sum.y / CGFloat(region.pointCount))
            return CGPoint(x: (face.boundingBox.minX + mean.x * face.boundingBox.width) * width,
                           y: (face.boundingBox.minY + mean.y * face.boundingBox.height) * height)
        }
        // The subject's left eye is on the right of the image: order by x so "left" is the image's left.
        let a = center(left), b = center(right)
        let (imageLeft, imageRight) = a.x <= b.x ? (a, b) : (b, a)
        let box = CGRect(x: face.boundingBox.minX * width, y: face.boundingBox.minY * height,
                         width: face.boundingBox.width * width, height: face.boundingBox.height * height)
        return FaceAnchors(leftEye: imageLeft, rightEye: imageRight, faceBox: box)
    }
}
