//
//  AudioAdjustmentTap.swift
//  EngineKit
//
//  Real-time pitch shifting for an audio-mix input track, used to make a voice
//  deeper or higher ("voz grave o aguda"). Built on `MTAudioProcessingTap`
//  hosting an `AUNewTimePitch` audio unit — the same approach Apple's
//  AudioTapProcessor sample uses — so it works identically in AVPlayer preview
//  and AVAssetExportSession export.
//
//  NOTE: This C-interop tap is the most environment-sensitive piece of the
//  effects feature. Pitch is applied to the whole track (time-windowed pitch is
//  a future enhancement). Gain effects are handled separately by AudioMixBuilder
//  via volume ramps, which are simpler and time-accurate.
//

import AVFoundation
import AudioToolbox

/// Builds `MTAudioProcessingTap`s that apply a constant pitch shift.
enum AudioAdjustmentTap {

    /// Mutable state carried through the tap callbacks. Holds the hosted
    /// time-pitch audio unit and the audio format negotiated at `prepare`.
    final class Context {
        let pitchCents: Float
        var audioUnit: AudioUnit?
        var sampleRate: Float64 = 44_100
        var channels: UInt32 = 2

        init(pitchCents: Float) {
            self.pitchCents = pitchCents
        }
    }

    /// Create a processing tap that shifts pitch by `cents` (100 cents = 1
    /// semitone; AUNewTimePitch accepts -2400…2400). Returns nil on failure so
    /// the caller can fall back to an unprocessed track.
    static func makePitchTap(cents: Float) -> MTAudioProcessingTap? {
        let clamped = max(-2400, min(2400, cents))
        let context = Context(pitchCents: clamped)
        let clientInfo = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            `init`: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr, let unmanagedTap = tap else {
            // Balance the retain we did for clientInfo since init won't run.
            Unmanaged<Context>.fromOpaque(clientInfo).release()
            return nil
        }
        return unmanagedTap.takeRetainedValue()
    }

    // MARK: - Tap callbacks

    private static let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
        // Hand the retained Context through to tap storage; ownership transfers
        // from clientInfo to tapStorage and is released in finalize.
        tapStorageOut.pointee = clientInfo
    }

    private static let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<Context>.fromOpaque(storage).release()
    }

    private static let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
        let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        let asbd = processingFormat.pointee
        context.sampleRate = asbd.mSampleRate
        context.channels = asbd.mChannelsPerFrame

        // Instantiate AUNewTimePitch (a FormatConverter unit) and configure it
        // with the negotiated stream format on both scopes.
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_FormatConverter,
            componentSubType: kAudioUnitSubType_NewTimePitch,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { return }

        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let audioUnit = unit else { return }
        context.audioUnit = audioUnit

        var streamFormat = asbd
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                             &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                             &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        // Pull input from the tap's source via a render callback. The callback
        // needs the tap itself (to call MTAudioProcessingTapGetSourceAudio); the
        // tap outlives prepare→process→unprepare so an unretained pointer is safe.
        var renderCallback = AURenderCallbackStruct(
            inputProc: pitchRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(tap).toOpaque()
        )
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                             &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        AudioUnitInitialize(audioUnit)
        // Pitch parameter is expressed in cents.
        AudioUnitSetParameter(audioUnit, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, 0,
                              context.pitchCents, 0)
    }

    private static let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
        let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        if let audioUnit = context.audioUnit {
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
            context.audioUnit = nil
        }
    }

    private static let tapProcess: MTAudioProcessingTapProcessCallback = {
        tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
        let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        guard let audioUnit = context.audioUnit else {
            // No unit — pass audio through untouched.
            var localFlags = MTAudioProcessingTapFlags()
            var localFrames: CMItemCount = 0
            MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, &localFlags, nil, &localFrames)
            numberFramesOut.pointee = localFrames
            return
        }

        var timeStamp = AudioTimeStamp()
        timeStamp.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()
        let status = AudioUnitRender(audioUnit, &flags, &timeStamp, 0,
                                     UInt32(numberFrames), bufferListInOut)
        if status == noErr {
            numberFramesOut.pointee = numberFrames
        } else {
            flagsOut.pointee = MTAudioProcessingTapFlags()
            numberFramesOut.pointee = 0
        }
    }

    /// Render callback the time-pitch unit uses to pull the tap's source audio.
    private static let pitchRenderCallback: AURenderCallback = {
        refCon, _, _, _, inNumberFrames, ioData in
        guard let ioData = ioData else { return noErr }
        let tap = Unmanaged<MTAudioProcessingTap>.fromOpaque(refCon).takeUnretainedValue()
        var flags = MTAudioProcessingTapFlags()
        var framesProvided: CMItemCount = 0
        let status = MTAudioProcessingTapGetSourceAudio(
            tap, CMItemCount(inNumberFrames), ioData, &flags, nil, &framesProvided
        )
        return status == noErr ? noErr : status
    }
}
