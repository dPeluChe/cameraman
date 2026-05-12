//
//  ProjectEditorLeftPanel.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import SwiftUI
import EngineKit

struct ProjectAssetsBar: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var isExpanded: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private var collapsedSummary: Int {
        editor.project.takes.count + editor.project.timeline.segments.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .frame(width: 16, height: 16)

                        Text("Project Assets")
                            .font(.headline)

                        if !isExpanded, collapsedSummary > 0 {
                            Text("(\(collapsedSummary))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse project assets" : "Expand project assets")

                Spacer()

                Button {
                    startNewTake()
                } label: {
                    Label("Rec Take", systemImage: "record.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Record new take")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            if isExpanded {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        AssetGroup(title: "Sources") {
                            AssetChip(icon: "display", title: "Screen", subtitle: "Main")
                            if editor.project.primarySources?.camera != nil {
                                AssetChip(icon: "video.fill", title: "Camera", subtitle: "1080p")
                            }
                            if editor.project.primarySources?.audio != nil {
                                AssetChip(icon: "mic.fill", title: "Mic", subtitle: "Audio")
                                AssetChip(icon: "speaker.wave.2.fill", title: "System", subtitle: "Audio")
                            }
                        }

                        if !editor.project.takes.isEmpty {
                            AssetGroup(title: "Takes") {
                                ForEach(editor.project.takes) { take in
                                    AssetChip(icon: "video.badge.plus", title: take.name, subtitle: formattedDate(take.createdAt))
                                        .help("Drag onto the timeline to add this take")
                                        .onHover { hovering in
                                            if hovering {
                                                NSCursor.openHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                        .onDrag {
                                            NSItemProvider(object: take.id.uuidString as NSString)
                                        }
                                }
                            }
                        }

                        if !editor.project.timeline.segments.isEmpty {
                            AssetGroup(title: "Layers") {
                                ForEach(Array(editor.project.timeline.segments.enumerated()), id: \.element.id) { index, segment in
                                    AssetChip(
                                        icon: "film",
                                        title: "Segment \(index + 1)",
                                        subtitle: "\(String(format: "%.1f", segment.sourceOut - segment.sourceIn))s"
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(height: isExpanded ? 82 : 38)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func startNewTake() {
        NotificationCenter.default.post(
            name: .openRecordingWindow,
            object: nil,
            userInfo: ["projectId": editor.project.projectId]
        )
    }

    private func formattedDate(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}

struct AssetGroup<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            content()
        }
    }
}

struct AssetChip: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minWidth: 110, maxWidth: 200, alignment: .leading)
        .help(title)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

