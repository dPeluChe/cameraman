//
//  VideoContentShape.swift
//  EngineKit
//
//  Where a video actually draws. A motion is a full-frame clip with a small card in it,
//  so its frame says nothing about what the viewer sees.
//

import AVFoundation
import CoreGraphics

public struct VideoContentShape: Equatable, Sendable {
    public let naturalSize: CGSize
    /// Union of the opaque area across the clip, top-left origin, as fractions of the frame.
    public let bounds: CGRect

    private static let measuredWidth: CGFloat = 320
    /// Skips soft shadows, which would pad the box without being content.
    private static let alphaThreshold: UInt8 = 24

    /// - Parameter range: source seconds to look at; nil means the whole video.
    public static func measure(url: URL, range: ClosedRange<Double>? = nil, samples: Int = 12) async -> VideoContentShape? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: measuredWidth, height: measuredWidth)
        // With the default tolerance every sample lands on the same keyframe.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var bounds: CGRect?
        for sample in 0..<samples {
            let span = range ?? 0...duration.seconds
            let seconds = span.lowerBound + (span.upperBound - span.lowerBound) * (Double(sample) + 0.5) / Double(samples)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image,
                  let opaque = opaqueBounds(of: image) else { continue }
            bounds = bounds?.union(opaque) ?? opaque
        }
        return VideoContentShape(naturalSize: naturalSize, bounds: bounds ?? CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[y * context.bytesPerRow + x] >= alphaThreshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: Double(minX) / Double(width), y: Double(minY) / Double(height),
                      width: Double(maxX - minX + 1) / Double(width), height: Double(maxY - minY + 1) / Double(height))
    }
}
