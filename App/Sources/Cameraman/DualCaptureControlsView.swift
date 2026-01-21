//
//  DualCaptureControlsView.swift
//  Cameraman
//
//  Created by Droid on 2026-01-21.
//  Dual-capture configuration for screen + camera recording
//

import SwiftUI
import AVFoundation
import EngineKit

/// Professional dual-capture controls for screen + camera
struct DualCaptureControlsView: View {
    @StateObject private var viewModel = DualCaptureViewModel()
    @State private var showCameraSelector = false
    @State private var showMicrophoneSelector = false
    let onConfigure: (DualCaptureConfiguration) -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            header

            Divider()
                .background(Color.white.opacity(0.15))

            // Screen capture section
            screenCaptureSection

            // Camera capture section
            cameraCaptureSection

            // Audio capture section
            audioCaptureSection

            // Preview section
            if viewModel.showPreview {
                previewSection
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Start button
            startButton
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .sheet(isPresented: $showCameraSelector) {
            CameraSelectorView(selectedDevice: $viewModel.selectedCamera)
        }
        .sheet(isPresented: $showMicrophoneSelector) {
            MicrophoneSelectorView(selectedDevice: $viewModel.selectedMicrophone)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "video.badge.video.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording Configuration")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Configure your screen and camera capture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.showPreview.toggle()
                } label: {
                    Image(systemName: viewModel.showPreview ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.showPreview ? "Hide Preview" : "Show Preview")
            }
        }
    }

    private var screenCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "display")
                    .foregroundStyle(.blue)

                Text("Screen Capture")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Toggle("", isOn: $viewModel.includeScreen)
                    .toggleStyle(.switch)
            }

            if viewModel.includeScreen {
                VStack(alignment: .leading, spacing: 10) {
                    // Source selector
                    Button {
                        // Show source selector
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.on.rectangle")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.selectedScreenSource)
                                    .font(.caption)

                                Text("Click to change")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    // Quality settings
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resolution")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Resolution", selection: $viewModel.screenResolution) {
                                Text("4K (3840×2160)").tag(ScreenResolution.uhd4k)
                                Text("1080p (1920×1080)").tag(ScreenResolution.fhd1080)
                                Text("720p (1280×720)").tag(ScreenResolution.hd720)
                            }
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Frame Rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Frame Rate", selection: $viewModel.screenFrameRate) {
                                Text("60 fps").tag(60)
                                Text("30 fps").tag(30)
                                Text("24 fps").tag(24)
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    private var cameraCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundStyle(.purple)

                Text("Camera Capture")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Toggle("", isOn: $viewModel.includeCamera)
                    .toggleStyle(.switch)
            }

            if viewModel.includeCamera {
                VStack(alignment: .leading, spacing: 10) {
                    // Camera selector
                    Button {
                        showCameraSelector = true
                    } label: {
                        HStack {
                            Image(systemName: "video.circle.fill")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.selectedCamera?.localizedName ?? "No Camera Selected")
                                    .font(.caption)

                                Text("Click to select camera")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    // Camera quality and position
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resolution")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Camera Resolution", selection: $viewModel.cameraResolution) {
                                Text("1080p").tag(CameraResolution.hd1080)
                                Text("720p").tag(CameraResolution.hd720)
                            }
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Position")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Position", selection: $viewModel.cameraPosition) {
                                Text("Top Right").tag(CameraPosition.topRight)
                                Text("Top Left").tag(CameraPosition.topLeft)
                                Text("Bottom Right").tag(CameraPosition.bottomRight)
                                Text("Bottom Left").tag(CameraPosition.bottomLeft)
                                Text("Center").tag(CameraPosition.center)
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    private var audioCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.green)

                Text("Audio Capture")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 10) {
                // System audio
                HStack {
                    Toggle("System Audio", isOn: $viewModel.includeSystemAudio)
                        .toggleStyle(.switch)

                    Spacer()

                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(viewModel.includeSystemAudio ? .green : .secondary)
                }

                // Microphone
                HStack {
                    Toggle("Microphone", isOn: $viewModel.includeMicrophone)
                        .toggleStyle(.switch)

                    Spacer()

                    Button {
                        showMicrophoneSelector = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.selectedMicrophone?.localizedName ?? "None")
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.includeMicrophone)
                }
            }
            .padding(.leading, 28)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Preview")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack {
                    // Screen preview (background)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "display")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        )

                    // Camera preview (overlay)
                    if viewModel.includeCamera {
                        let cameraFrame = calculateCameraFrame(containerSize: proxy.size)

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.purple.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.purple)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.purple, lineWidth: 2)
                            )
                            .frame(width: cameraFrame.width, height: cameraFrame.height)
                            .position(x: cameraFrame.midX, y: cameraFrame.midY)
                    }
                }
            }
            .frame(height: 200)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
    }

    private var startButton: some View {
        Button {
            let config = DualCaptureConfiguration(
                includeScreen: viewModel.includeScreen,
                includeCamera: viewModel.includeCamera,
                includeSystemAudio: viewModel.includeSystemAudio,
                includeMicrophone: viewModel.includeMicrophone,
                screenResolution: viewModel.screenResolution,
                screenFrameRate: viewModel.screenFrameRate,
                cameraResolution: viewModel.cameraResolution,
                cameraPosition: viewModel.cameraPosition
            )
            onConfigure(config)
        } label: {
            HStack {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 20))

                Text("Start Recording")
                    .font(.system(size: 16))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.red, Color.red.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canStartRecording)
    }

    private func calculateCameraFrame(containerSize: CGSize) -> CGRect {
        let cameraWidth = containerSize.width * 0.3
        let cameraHeight = cameraWidth * (9 / 16) // 16:9 aspect ratio

        let padding: CGFloat = 20

        switch viewModel.cameraPosition {
        case .topRight:
            return CGRect(
                x: containerSize.width - cameraWidth - padding,
                y: padding,
                width: cameraWidth,
                height: cameraHeight
            )
        case .topLeft:
            return CGRect(
                x: padding,
                y: padding,
                width: cameraWidth,
                height: cameraHeight
            )
        case .bottomRight:
            return CGRect(
                x: containerSize.width - cameraWidth - padding,
                y: containerSize.height - cameraHeight - padding,
                width: cameraWidth,
                height: cameraHeight
            )
        case .bottomLeft:
            return CGRect(
                x: padding,
                y: containerSize.height - cameraHeight - padding,
                width: cameraWidth,
                height: cameraHeight
            )
        case .center:
            return CGRect(
                x: (containerSize.width - cameraWidth) / 2,
                y: (containerSize.height - cameraHeight) / 2,
                width: cameraWidth,
                height: cameraHeight
            )
        }
    }
}

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
        let videoDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices

        if let defaultCamera = videoDevices.first {
            selectedCamera = defaultCamera
        }

        // Find default microphone using AVCaptureDevice.DiscoverySession
        let audioDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
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
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified).devices
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(videoDevices, id: \.uniqueID) { device in
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
                                Text("\(device.resolutionWidth ?? 0)×\(device.resolutionHeight ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone], mediaType: .audio, position: .unspecified).devices
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(audioDevices, id: \.uniqueID) { device in
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

// MARK: - Preview

#Preview {
    DualCaptureControlsView { config in
        print("Configuration: \(config)")
    }
}
