//
//  SubtitleEditorView.swift
//  App
//
//  Right-panel editor for subtitles: global style (typography color, position,
//  size, background) plus a per-cue list for editing text, color, and timing.
//  Cues come from the transcript; the style only appears once there are some.
//

import SwiftUI
import EngineKit

struct SubtitleEditorView: View {
    @ObservedObject var editor: ProjectEditor
    /// Seek callback so tapping a cue moves the playhead.
    var onSeek: ((TimeInterval) -> Void)? = nil
    /// Opens the transcript, which makes the cues.
    let onOpenTranscript: () -> Void

    // Local, editable copy of the global style. Applied explicitly so dragging a
    // slider doesn't spam undo snapshots (each apply rebuilds every cue).
    @State private var draftStyle: Project.SubtitleStyle = .default
    @State private var hasBackground: Bool = false
    @State private var backgroundColor: Color = .black
    @State private var editingTexts: [UUID: String] = [:]

    private var subtitles: [Project.Overlay] {
        editor.project.subtitles.sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if subtitles.isEmpty {
                emptyState
            } else {
                styleSection
                Divider()
                cueListSection
            }
        }
        .onAppear(perform: loadDraft)
    }

    // MARK: - Style

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack {
                Text("Text color")
                    .font(.caption)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: draftStyle.textColor) },
                    set: { draftStyle.textColor = $0.toHex() ?? "#FFFFFF" }
                ))
                .labelsHidden()
            }

            sliderRow(
                title: "Size",
                value: $draftStyle.fontSize,
                range: 16...96,
                display: { String(format: "%.0fpt", $0) }
            )

            sliderRow(
                title: "Vertical",
                value: $draftStyle.verticalPosition,
                range: 0...1,
                display: { String(format: "%.0f%%", $0 * 100) }
            )

            sliderRow(
                title: "Width",
                value: $draftStyle.width,
                range: 0.2...1.0,
                display: { String(format: "%.0f%%", $0 * 100) }
            )

            Toggle("Shadow", isOn: $draftStyle.shadow)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)

            Toggle("Background box", isOn: $hasBackground)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)

            if hasBackground {
                HStack {
                    Text("Box color")
                        .font(.caption)
                    Spacer()
                    ColorPicker("", selection: $backgroundColor)
                        .labelsHidden()
                }
            }

            Button {
                applyStyle()
            } label: {
                Text("Apply style to all")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
    }

    // MARK: - Cue list

    private var cueListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(subtitles.count) cues")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                addCueButton
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                Button(action: onOpenTranscript) {
                    Label("Transcript", systemImage: "text.quote")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Open the transcript to edit it or create the subtitles again")
                Button(role: .destructive) {
                    Task { await editor.clearSubtitles() }
                } label: {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Remove all subtitles")
            }

            ForEach(subtitles) { cue in
                cueRow(cue)
                Divider()
            }
        }
    }

    private func cueRow(_ cue: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    onSeek?(cue.start)
                } label: {
                    Text(timecode(cue.start))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                ColorPicker("", selection: Binding(
                    get: { Color(hex: cue.style.color ?? "#FFFFFF") },
                    set: { newColor in
                        Task { await editor.styleSubtitle(id: cue.id, textColor: newColor.toHex() ?? "#FFFFFF") }
                    }
                ))
                .labelsHidden()
                .frame(width: 28)

                Button {
                    Task { await editor.deleteSubtitle(id: cue.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("Subtitle text", text: Binding(
                get: { editingTexts[cue.id] ?? cue.style.text ?? "" },
                set: { editingTexts[cue.id] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onSubmit {
                let newText = editingTexts[cue.id] ?? cue.style.text ?? ""
                Task { await editor.updateSubtitle(id: cue.id, text: newText) }
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onOpenTranscript) {
                PanelActionLabel("Generate Subtitles...", icon: "captions.bubble")
            }
            .buttonStyle(.borderedProminent)
            Text("Made on this Mac from what is said in the video.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            addCueButton
                .controlSize(.small)
        }
    }

    private var addCueButton: some View {
        Button {
            let start = subtitles.last?.end ?? 0
            Task { _ = await editor.addSubtitle(text: "New subtitle", start: start, end: start + 2) }
        } label: {
            Label("Add subtitle", systemImage: "plus")
        }
        .help("Add a subtitle after the last one")
    }

    // MARK: - Helpers

    private func loadDraft() {
        draftStyle = editor.project.subtitleStyle
        if let bg = draftStyle.backgroundColor {
            hasBackground = true
            backgroundColor = Color(hex: bg)
        } else {
            hasBackground = false
        }
    }

    private func applyStyle() {
        var style = draftStyle
        style.backgroundColor = hasBackground ? (backgroundColor.toHex() ?? "#000000") : nil
        Task { await editor.setSubtitleStyle(style) }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }

    private func timecode(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
