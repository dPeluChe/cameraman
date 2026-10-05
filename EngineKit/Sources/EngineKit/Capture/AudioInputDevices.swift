import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// A selectable audio input. `id` is the CoreAudio device UID, stable across reconnects.
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public enum AudioInputDevices {
    public static func list() -> [AudioInputDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInMicrophone]
        if #available(macOS 14.0, *) { types = [.microphone, .external] } else { types.append(.externalUnknown) }
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified)
        return session.devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Routes the engine's input node to the device with this UID. Returns false when the device
    /// is gone, so the caller keeps the system default instead of failing the recording.
    @discardableResult
    static func route(_ engine: AVAudioEngine, toDeviceUID uid: String?) -> Bool {
        guard let uid, var deviceID = deviceID(forUID: uid), let unit = engine.inputNode.audioUnit else { return false }
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        return status == noErr
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), qualifier, &size, &deviceID
            )
        }
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}
