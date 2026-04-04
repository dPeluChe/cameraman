//
//  MediaItemInspector.swift
//  App
//
//  Media item inspector for configuring imported images
//

import SwiftUI
import EngineKit

struct MediaItemInspectorView: View {
    @ObservedObject var editor: ProjectEditor
    var selectedMediaItemId: UUID?

    private var selectedItem: Project.MediaItem? {
        guard let id = selectedMediaItemId else { return nil }
        return editor.project.mediaItems.first { $0.id == id }
    }

    var body: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 12) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.subheadline)
                    TextField("Name", text: Binding(
                        get: { item.name },
                        set: { newName in Task { await editor.updateMediaItem(id: item.id, name: newName) } }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Position preset
                if item.type == .image {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Position")
                            .font(.subheadline)
                        Picker("Position", selection: Binding(
                            get: {
                                if let pos = item.position {
                                    return Project.MediaPositionPreset.allCases.first { preset in
                                        let presetPos = preset.toPosition(w: pos.w, h: pos.h)
                                        return abs(presetPos.x - pos.x) < 0.01 &&
                                               abs(presetPos.y - pos.y) < 0.01 &&
                                               abs(presetPos.w - pos.w) < 0.01 &&
                                               abs(presetPos.h - pos.h) < 0.01
                                    } ?? .center
                                }
                                return .center
                            },
                            set: { preset in
                                let currentW = item.position?.w ?? Project.MediaPosition.defaultOverlaySize
                            let currentH = item.position?.h ?? Project.MediaPosition.defaultOverlaySize
                            Task { await editor.updateMediaItem(id: item.id, position: preset.toPosition(w: currentW, h: currentH)) }
                            }
                        )) {
                            ForEach(Project.MediaPositionPreset.allCases, id: \.self) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Opacity
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opacity: \(Int(item.opacity * 100))%")
                            .font(.subheadline)
                        Slider(value: Binding(
                            get: { item.opacity },
                            set: { newOpacity in Task { await editor.updateMediaItem(id: item.id, opacity: newOpacity) } }
                        ), in: 0...1)
                    }
                }

                // Volume (for audio)
                if item.type == .audio {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volume: \(Int(item.volume * 100))%")
                            .font(.subheadline)
                        Slider(value: Binding(
                            get: { item.volume },
                            set: { newVolume in Task { await editor.updateMediaItem(id: item.id, volume: newVolume) } }
                        ), in: 0...1)
                    }

                    Toggle("Muted", isOn: Binding(
                        get: { item.isMuted },
                        set: { muted in Task { await editor.updateMediaItem(id: item.id, isMuted: muted) } }
                    ))
                }

                // Duration
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration: \(String(format: "%.1fs", item.duration))")
                        .font(.subheadline)
                    Slider(value: Binding(
                        get: { item.duration },
                        set: { newDuration in Task { await editor.updateMediaItem(id: item.id, duration: max(0.5, newDuration)) } }
                    ), in: 0.5...60, step: 0.5)
                }

                // Delete button
                Button(role: .destructive) {
                    Task { await editor.removeMediaItem(id: item.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .padding(.top, 8)
            }
            .padding()
        } else {
            Text("Select an image or audio item in the timeline")
                .foregroundColor(.secondary)
                .padding()
        }
    }
}
