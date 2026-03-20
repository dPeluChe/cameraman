//
//  DualCaptureControlsModels.swift
//  Cameraman
//
//  Extracted from DualCaptureControlsView.swift
//  Configuration models and device selector views for dual capture
//

import SwiftUI
import AVFoundation

// MARK: - View Model

@MainActor
class DualCaptureViewModel: ObservableObject {
    @Published var includeScreen = true
    @Published var includeCamera = true
    @Published var includeSystemAudio = true
    @Published var includeMicrophone = false

    @Published var screenResolution: ScreenResolution = .fhd1080
    @Published var screenFrameRate: Int = 60
    @Published var selectedScreenSource = "Main Display"

    @Published var cameraResolution: CameraResolution = .hd720
    @Published var cameraPosition: CameraPosition = .topRight
    @Published var selectedCamera: AVCaptureDevice?

    @Published var selectedMicrophone: AVCaptureDevice?
    @Published var showPreview = true

    var canStartRecording: Bool {
        includeScreen || includeCamera
    }

    init() {
        // Load default camera
        loadDefaultDevices()
    }

    private func loadDefaultDevices() {
        // Find default camera using AVCaptureDevice.DiscoverySession
        let cameraDeviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            cameraDeviceTypes = [.builtInWideAngleCamera, .external]
        } else {
            cameraDeviceTypes = [.builtInWideAngleCamera, .externalUnknown]
        }

        let videoDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: cameraDeviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices

        if let defaultCamera = videoDevices.first {
            selectedCamera = defaultCamera
        }

        // Find default microphone using AVCaptureDevice.DiscoverySession
        let microphoneDeviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            microphoneDeviceTypes = [.microphone]
        } else {
            microphoneDeviceTypes = [.builtInMicrophone]
        }

        let audioDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: microphoneDeviceTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices

        if let defaultMic = audioDevices.first {
            selectedMicrophone = defaultMic
        }
    }
}

// MARK: - Configuration Models

struct DualCaptureConfiguration {
    let includeScreen: Bool
    let includeCamera: Bool
    let includeSystemAudio: Bool
    let includeMicrophone: Bool
    let screenResolution: ScreenResolution
    let screenFrameRate: Int
    let cameraResolution: CameraResolution
    let cameraPosition: CameraPosition
}

enum ScreenResolution {
    case uhd4k
    case fhd1080
    case hd720

    var width: Int {
        switch self {
        case .uhd4k: return 3840
        case .fhd1080: return 1920
        case .hd720: return 1280
        }
    }

    var height: Int {
        switch self {
        case .uhd4k: return 2160
        case .fhd1080: return 1080
        case .hd720: return 720
        }
    }
}

enum CameraResolution {
    case hd1080
    case hd720

    var width: Int {
        switch self {
        case .hd1080: return 1920
        case .hd720: return 1280
        }
    }

    var height: Int {
        switch self {
        case .hd1080: return 1080
        case .hd720: return 720
        }
    }
}

enum CameraPosition {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
    case center
}

// MARK: - Device Selectors

struct CameraSelectorView: View {
    @Binding var selectedDevice: AVCaptureDevice?
    @Environment(\.dismiss) private var dismiss

    private var videoDevices: [AVCaptureDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.builtInWideAngleCamera, .external]
        } else {
            deviceTypes = [.builtInWideAngleCamera, .externalUnknown]
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(videoDevices, id: \.uniqueID) { (device: AVCaptureDevice) in
                    Button {
                        selectedDevice = device
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "video.circle.fill")
                                .foregroundStyle(.purple)

                            VStack(alignment: .leading) {
                                Text(device.localizedName)
                                    .font(.body)
                            }
                            Spacer()
                            if selectedDevice?.uniqueID == device.uniqueID {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Select") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDevice == nil)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 400, height: 300)
    }
}

struct MicrophoneSelectorView: View {
    @Binding var selectedDevice: AVCaptureDevice?
    @Environment(\.dismiss) private var dismiss

    private var audioDevices: [AVCaptureDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone]
        } else {
            deviceTypes = [.builtInMicrophone]
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(audioDevices, id: \.uniqueID) { (device: AVCaptureDevice) in
                    Button {
                        selectedDevice = device
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "mic.circle.fill")
                                .foregroundStyle(.green)

                            VStack(alignment: .leading) {
                                Text(device.localizedName)
                                    .font(.body)
                            }
                            Spacer()
                            if selectedDevice?.uniqueID == device.uniqueID {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Select") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDevice == nil)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 400, height: 300)
    }
}
