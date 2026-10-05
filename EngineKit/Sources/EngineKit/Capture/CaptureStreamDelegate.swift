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

/// Delegate for SCStream lifecycle events. Samples arrive through `CaptureStreamOutput`; this
/// exists so a stream the system stops (display unplugged, permission revoked) is not silent.
final class StreamDelegate: NSObject, SCStreamDelegate {
    private let onStop: @Sendable (Error) -> Void

    init(onStop: @escaping @Sendable (Error) -> Void) {
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        handleStop(error)
    }

    func handleStop(_ error: Error) {
        let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "CaptureStream")
        logger.error("Stream stopped with error: \(error.localizedDescription)")
        onStop(error)
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
