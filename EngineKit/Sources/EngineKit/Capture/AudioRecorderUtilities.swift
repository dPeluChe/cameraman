//
//  AudioRecorderUtilities.swift
//  EngineKit
//
//  Shared utilities for AVAudioEngine-based recorders.
//

import Foundation
import AVFoundation

enum AudioRecorderUtilities {

    /// Standard AAC recording settings used by mic and voiceover recorders.
    static func aacSettings(format: AVAudioFormat, bitRate: Int = 128_000) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: format.channelCount,
            AVSampleRateKey: format.sampleRate,
            AVEncoderBitRateKey: bitRate
        ]
    }

    /// Deep-copy a PCM buffer so it survives past the tap callback's lifetime.
    /// The audio engine reuses the underlying buffer storage as soon as the
    /// callback returns; reading or writing from a background thread after
    /// that point reads garbage.
    static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else { return nil }
        copy.frameLength = buffer.frameLength
        let ch = Int(buffer.format.channelCount)
        let len = Int(buffer.frameLength)
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for c in 0..<ch { dst[c].update(from: src[c], count: len) }
        } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
            for c in 0..<ch { dst[c].update(from: src[c], count: len) }
        } else if let src = buffer.int32ChannelData, let dst = copy.int32ChannelData {
            for c in 0..<ch { dst[c].update(from: src[c], count: len) }
        } else {
            return nil
        }
        return copy
    }
}
