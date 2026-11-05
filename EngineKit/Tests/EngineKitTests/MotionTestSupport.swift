import AVFoundation
import XCTest

/// Reading frames and pixels back out of rendered motion videos.
enum MotionTestSupport {
    static func tempURL(_ name: String = "motion.mov") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    static func frame(of url: URL, at seconds: Double) throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
    }

    /// RGBA of the pixel at (x, y), top-left origin, premultiplied alpha as stored.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[1], data[2], data[3])
    }

    /// Share of pixels that are not fully transparent.
    static func coverage(_ image: CGImage) -> Double {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let visible = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 8 }.count
        return Double(visible) / Double(image.width * image.height)
    }
}
