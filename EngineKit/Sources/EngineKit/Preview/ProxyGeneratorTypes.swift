//
//  ProxyGeneratorTypes.swift
//  EngineKit
//
//  Extracted from ProxyGenerator.swift — types, configuration, and errors
//

import Foundation
import AVFoundation

extension ProxyGenerator {
    /// Proxy generation configuration
    public struct Configuration: Sendable {
        public let width: Int
        public let height: Int
        public let codec: AVVideoCodecType
        public let outputFormat: AVFileType
        public let targetBitrate: Int
        public let preserveAspectRatio: Bool
        public let frameRate: Double

        public init(
            width: Int = 1280,
            height: Int = 720,
            codec: AVVideoCodecType = .h264,
            outputFormat: AVFileType = .mov,
            targetBitrate: Int = 2,
            preserveAspectRatio: Bool = true,
            frameRate: Double = 30.0
        ) {
            self.width = width
            self.height = height
            self.codec = codec
            self.outputFormat = outputFormat
            self.targetBitrate = targetBitrate
            self.preserveAspectRatio = preserveAspectRatio
            self.frameRate = frameRate
        }

        public static let `default` = Configuration()

        public static let hd1080 = Configuration(
            width: 1920,
            height: 1080,
            targetBitrate: 5,
            frameRate: 30.0
        )

        public static let sd480 = Configuration(
            width: 854,
            height: 480,
            targetBitrate: 1,
            frameRate: 24.0
        )
    }

    /// Proxy generation result
    public struct ProxyResult: Sendable {
        public let proxyPath: String
        public let sourcePath: String
        public let duration: TimeInterval
        public let sizeBytes: UInt64
        public let originalSizeBytes: UInt64
        public let compressionRatio: Double

        public init(
            proxyPath: String,
            sourcePath: String,
            duration: TimeInterval,
            sizeBytes: UInt64,
            originalSizeBytes: UInt64
        ) {
            self.proxyPath = proxyPath
            self.sourcePath = sourcePath
            self.duration = duration
            self.sizeBytes = sizeBytes
            self.originalSizeBytes = originalSizeBytes
            self.compressionRatio = originalSizeBytes > 0 ? Double(originalSizeBytes) / Double(sizeBytes) : 1.0
        }
    }

    /// Proxy generation error types
    public enum ProxyError: Error, Equatable, Sendable {
        case sourceFileNotFound(String)
        case sourceFileCorrupted(String)
        case failedToCreateAsset(String)
        case failedToCreateReader(String)
        case failedToCreateWriter(String)
        case failedToStartWriting(String)
        case failedToStartSession(String)
        case failedToAppendSample(String)
        case failedToFinishWriting(String)
        case insufficientDiskSpace(required: UInt64, available: UInt64)
        case cancelled

        public var localizedDescription: String {
            switch self {
            case .sourceFileNotFound(let path):
                return "Source file not found: \(path)"
            case .sourceFileCorrupted(let path):
                return "Source file is corrupted or unreadable: \(path)"
            case .failedToCreateAsset(let reason):
                return "Failed to create asset: \(reason)"
            case .failedToCreateReader(let reason):
                return "Failed to create asset reader: \(reason)"
            case .failedToCreateWriter(let reason):
                return "Failed to create asset writer: \(reason)"
            case .failedToStartWriting(let reason):
                return "Failed to start writing: \(reason)"
            case .failedToStartSession(let reason):
                return "Failed to start session: \(reason)"
            case .failedToAppendSample(let reason):
                return "Failed to append sample: \(reason)"
            case .failedToFinishWriting(let reason):
                return "Failed to finish writing: \(reason)"
            case .insufficientDiskSpace(let required, let available):
                return "Insufficient disk space: required \(required) bytes, available \(available) bytes"
            case .cancelled:
                return "Proxy generation was cancelled"
            }
        }
    }
}
