//
//  CaptureStreamDelegate.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import os.log

/// Delegate for handling SCStream events
final class StreamDelegate: NSObject, SCStreamDelegate {
    private let onSampleBuffer: (CMSampleBuffer, SCStreamOutputType) -> Void

    init(onSampleBuffer: @escaping (CMSampleBuffer, SCStreamOutputType) -> Void) {
        self.onSampleBuffer = onSampleBuffer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        onSampleBuffer(sampleBuffer, type)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "CaptureStream")
        logger.error("Stream stopped with error: \(error.localizedDescription)")
    }
}

/// Custom SCStreamOutput for handling samples
final class CaptureStreamOutput: NSObject, SCStreamOutput {
    private let onSample: (CMSampleBuffer, SCStreamOutputType) -> Void

    init(onSample: @escaping (CMSampleBuffer, SCStreamOutputType) -> Void) {
        self.onSample = onSample
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        onSample(sampleBuffer, type)
    }
}
