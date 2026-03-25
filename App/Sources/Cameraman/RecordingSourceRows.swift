//
//  FloatingSourceSelectorView+Subviews.swift
//  Cameraman
//
//  Extracted from FloatingSourceSelectorView.swift
//  Source type buttons and professional source row views
//

import SwiftUI
import EngineKit

// MARK: - Source Type Button

struct FloatingSourceTypeButton: View {
    let type: FloatingSourceType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 14))
                Text(type.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .secondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

enum FloatingSourceType: CaseIterable {
    case display
    case window
    case application

    var label: String {
        switch self {
        case .display: return "Displays"
        case .window: return "Windows"
        case .application: return "Apps"
        }
    }

    var icon: String {
        switch self {
        case .display: return "display"
        case .window: return "rectangle.on.rectangle"
        case .application: return "app.fill"
        }
    }

    var rawValue: SourceSelectorViewModel.SourceTab {
        switch self {
        case .display: return .display
        case .window: return .window
        case .application: return .application
        }
    }
}

// MARK: - Professional Source Rows

struct ProfessionalDisplaySourceRow: View {
    let source: SourceSelector.DisplaySource
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 56, height: 40)

                    Image(systemName: "display")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text("\(source.width)x\(source.height)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(source.refreshRate)) Hz")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if source.isMain {
                            badge("Main", color: .green)
                        }
                    }
                }

                Spacer()

                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Preview")
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color ?? .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((color ?? .secondary).opacity(0.15))
            .cornerRadius(4)
    }
}

struct ProfessionalWindowSourceRow: View {
    let source: SourceSelector.WindowSource
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 48, height: 38)

                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 16))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(source.applicationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text("\(source.width)x\(source.height)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !source.isOnScreen {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("Off-screen")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.purple.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProfessionalApplicationSourceRow: View {
    let source: SourceSelector.ApplicationSource
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(source.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
