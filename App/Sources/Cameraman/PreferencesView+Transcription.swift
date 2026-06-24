//
//  PreferencesView+Transcription.swift
//  App
//
//  Transcription settings: on-device model selection + provider (future).
//

import SwiftUI
import EngineKit

struct TranscriptionPreferencesView: View {
    @AppStorage(TranscriptionModelPreference.key) private var model = TranscriptionEngine.Options.Model.base.rawValue

    private let isAvailable = TranscriptionEngine.isAvailable

    // Approximate CoreML download sizes — informational only.
    private let modelInfo: [(value: String, label: String, size: String)] = [
        ("base", "Base", "~150 MB"),
        ("small", "Small", "~500 MB"),
        ("medium", "Medium", "~1.5 GB"),
        ("large", "Large (v3)", "~3 GB")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if !isAvailable {
                Label(
                    "On-device transcription requires a Mac with Apple Silicon — not available on this machine.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection("Model") {
                Picker("Whisper model", selection: $model) {
                    ForEach(modelInfo, id: \.value) { info in
                        Text("\(info.label) — \(info.size)").tag(info.value)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!isAvailable)

                Text("Larger models are more accurate but slower and use more memory. The model is downloaded automatically the first time you transcribe (kept on disk afterward).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection("Provider") {
                LabeledContent("Engine", value: "WhisperKit (on-device, CoreML/ANE)")

                Text("Transcription runs fully on-device. Cloud providers may be added later for Intel Macs and larger models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}
