//
//  ProxyGenerator+Helpers.swift
//  EngineKit
//
//  Private helpers for proxy generation: sizing, disk, frame resizing.
//  Extracted from ProxyGenerator.swift.
//

import Foundation
import AVFoundation
import CoreGraphics

extension ProxyGenerator {

    // MARK: - Disk Space

    func estimateProxySize(sourceSizeBytes: UInt64, configuration: Configuration) -> UInt64 {
        let sourcePixels = 1920 * 1080
        let proxyPixels = configuration.width * configuration.height
        let resolutionRatio = Double(proxyPixels) / Double(sourcePixels)
        let sourceBitrate = 20.0
        let proxyBitrate = Double(configuration.targetBitrate)
        let bitrateRatio = proxyBitrate / sourceBitrate
        let estimatedRatio = resolutionRatio * bitrateRatio
        return UInt64(Double(sourceSizeBytes) * estimatedRatio * 1.2)
    }

    func checkDiskSpace(for sizeBytes: UInt64, at path: String) throws -> Bool {
        getAvailableDiskSpace(at: path) >= sizeBytes
    }

    func getAvailableDiskSpace(at path: String) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.systemFreeSize] as? UInt64 ?? 0
    }

    // MARK: - Output Sizing

    func calculateOutputSize(
        sourceSize: CoreFoundation.CGSize,
        config: Configuration
    ) -> CoreFoundation.CGSize {
        if config.preserveAspectRatio {
            let sourceAspect = sourceSize.width / sourceSize.height
            let configAspect = Double(config.width) / Double(config.height)
            if sourceAspect > configAspect {
                let height = Double(config.width) / sourceAspect
                return CoreFoundation.CGSize(width: config.width, height: Int(height))
            } else {
                let width = Double(config.height) * sourceAspect
                return CoreFoundation.CGSize(width: Int(width), height: config.height)
            }
        }
        return CoreFoundation.CGSize(width: config.width, height: config.height)
    }

    func calculateDrawRect(
        sourceSize: CoreFoundation.CGSize,
        destSize: CoreFoundation.CGSize,
        preserveAspectRatio: Bool
    ) -> CoreFoundation.CGRect {
        if preserveAspectRatio {
            let sourceAspect = sourceSize.width / sourceSize.height
            let destAspect = destSize.width / destSize.height
            if sourceAspect > destAspect {
                let height = destSize.width / sourceAspect
                let y = (destSize.height - height) / 2
                return CoreFoundation.CGRect(x: 0, y: y, width: destSize.width, height: height)
            } else {
                let width = destSize.height * sourceAspect
                let x = (destSize.width - width) / 2
                return CoreFoundation.CGRect(x: x, y: 0, width: width, height: destSize.height)
            }
        }
        return CoreFoundation.CGRect(x: 0, y: 0, width: destSize.width, height: destSize.height)
    }

    // MARK: - CGContext

    func createCGContext(from pixelBuffer: CVPixelBuffer) -> CGContext? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        return CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
    }
}
