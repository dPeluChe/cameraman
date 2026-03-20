//
//  ChapterManagementView+Subviews.swift
//  App
//
//  Extracted from ChapterManagementView.swift
//  Row views and flow layout for chapter management
//

import SwiftUI
import EngineKit
import CoreFoundation

// MARK: - Chapter Row

/// Row view for a single chapter in the project
struct ChapterRow: View {
    let chapter: Project.Chapter
    let isEditing: Bool
    @Binding var editedTitle: String
    @Binding var editedSummary: String
    @Binding var editedKeywords: String
    let onSeek: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // Editing mode
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Chapter Title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)

                    TextField("Summary (optional)", text: $editedSummary, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    TextField("Keywords (comma-separated)", text: $editedKeywords)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.bordered)

                        Button("Save") {
                            onSave()
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            } else {
                // Display mode
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .font(.title2)
                        .foregroundStyle(Color.blue)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(timeRangeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let summary = chapter.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if !chapter.keywords.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(chapter.keywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: onSeek) {
                            Image(systemName: "play.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Seek to chapter start")

                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit chapter")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete chapter")
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
    }

    private var timeRangeText: String {
        let start = String(format: "%.1f", chapter.startTime)
        let end = String(format: "%.1f", chapter.endTime)
        let duration = String(format: "%.1f", chapter.duration)
        return "\(start)s - \(end)s (\(duration)s)"
    }
}

// MARK: - Suggested Chapter Row

/// Row view for a suggested chapter from AI
struct SuggestedChapterRow: View {
    let suggestion: Suggestion
    let onSeek: () -> Void
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                if let title = suggestion.metadata("title", as: String.self) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("Suggested Chapter")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                    Text("\(Int(suggestion.confidence * 100))% confidence")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                if let summary = suggestion.metadata("summary", as: String.self), !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onSeek) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preview chapter")

                Button(action: onApply) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Apply chapter")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss suggestion")
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var timeRangeText: String {
        let start = String(format: "%.1f", suggestion.timelineIn)
        let end = String(format: "%.1f", suggestion.timelineOut)
        let duration = String(format: "%.1f", suggestion.timelineOut - suggestion.timelineIn)
        return "\(start)s - \(end)s (\(duration)s)"
    }
}

// MARK: - Flow Layout

/// Simple flow layout for keyword tags
struct FlowLayout: Layout {
    var spacing: Double = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CoreFoundation.CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CoreFoundation.CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CoreFoundation.CGSize = .zero
        var positions: [CoreFoundation.CGPoint] = []

        init(in maxWidth: Double, subviews: Subviews, spacing: Double) {
            var currentX: Double = 0
            var currentY: Double = 0
            var lineHeight: Double = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CoreFoundation.CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CoreFoundation.CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
