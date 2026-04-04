//
//  AudioProcessing.swift
//  EngineKit
//
//  Audio processing utilities: noise gate, echo cancellation
//

import Foundation
import AVFoundation
import Accelerate

public final class AudioProcessor {
    
    public struct Configuration: Sendable {
        public var noiseGateThreshold: Float
        public var noiseGateAttack: TimeInterval
        public var noiseGateRelease: TimeInterval
        public var echoCancellationEnabled: Bool
        public var echoCancellationLevel: Float
        
        public init(
            noiseGateThreshold: Float = -40.0,
            noiseGateAttack: TimeInterval = 0.01,
            noiseGateRelease: TimeInterval = 0.1,
            echoCancellationEnabled: Bool = false,
            echoCancellationLevel: Float = 0.5
        ) {
            self.noiseGateThreshold = noiseGateThreshold
            self.noiseGateAttack = noiseGateAttack
            self.noiseGateRelease = noiseGateRelease
            self.echoCancellationEnabled = echoCancellationEnabled
            self.echoCancellationLevel = echoCancellationLevel
        }
    }
    
    private var config: Configuration
    private var isGateOpen: Bool = false
    private var gateEnvelope: Float = 0.0
    private let sampleRate: Double
    
    public init(configuration: Configuration = Configuration(), sampleRate: Double = 48000) {
        self.config = configuration
        self.sampleRate = sampleRate
    }
    
    public func updateConfiguration(_ newConfig: Configuration) {
        self.config = newConfig
    }
    
    public func process(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        for channel in 0..<channelCount {
            let data = channelData[channel]
            
            if config.noiseGateThreshold > -90 {
                applyNoiseGate(data: data, frameCount: frameLength)
            }
        }
        
        return buffer
    }
    
    private func applyNoiseGate(data: UnsafeMutablePointer<Float>, frameCount: Int) {
        var rms: Float = 0
        vDSP_measqv(data, 1, &rms, vDSP_Length(frameCount))
        rms = sqrt(rms)
        
        let thresholdLinear = pow(10, config.noiseGateThreshold / 20)
        
        let attackCoef = Float(exp(-1.0 / (config.noiseGateAttack * sampleRate)))
        let releaseCoef = Float(exp(-1.0 / (config.noiseGateRelease * sampleRate)))
        
        if rms > thresholdLinear {
            gateEnvelope = max(gateEnvelope, 1.0)
        } else {
            gateEnvelope *= releaseCoef
        }
        
        if gateEnvelope < 0.01 {
            isGateOpen = false
        } else if gateEnvelope > 0.99 {
            isGateOpen = true
        }
        
        if !isGateOpen {
            memset(data, 0, frameCount * MemoryLayout<Float>.size)
        }
    }
    
    public func getCurrentNoiseGateState() -> Bool {
        return isGateOpen
    }
}

public struct AudioProcessingConfiguration: Codable, Sendable {
    public var noiseGateEnabled: Bool
    public var noiseGateThreshold: Float
    public var echoCancellationEnabled: Bool
    public var echoCancellationIntensity: Float
    
    public init(
        noiseGateEnabled: Bool = false,
        noiseGateThreshold: Float = -40.0,
        echoCancellationEnabled: Bool = false,
        echoCancellationIntensity: Float = 0.5
    ) {
        self.noiseGateEnabled = noiseGateEnabled
        self.noiseGateThreshold = noiseGateThreshold
        self.echoCancellationEnabled = echoCancellationEnabled
        self.echoCancellationIntensity = echoCancellationIntensity
    }
    
    public static let `default` = AudioProcessingConfiguration()
    
    public static let aggressive = AudioProcessingConfiguration(
        noiseGateEnabled: true,
        noiseGateThreshold: -30.0,
        echoCancellationEnabled: true,
        echoCancellationIntensity: 0.7
    )
    
    public static let subtle = AudioProcessingConfiguration(
        noiseGateEnabled: true,
        noiseGateThreshold: -50.0,
        echoCancellationEnabled: true,
        echoCancellationIntensity: 0.3
    )
}
