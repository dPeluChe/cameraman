//
//  RecordingSourceSelectorView+Rows.swift
//  App
//
//  Extracted from RecordingSourceSelectorView.swift
//  Source row components
//

import SwiftUI
import EngineKit

struct DisplaySourceRow: View {
    let source: SourceSelector.DisplaySource
    let isSelected: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 44, height: 30)

                    Image(systemName: "display")
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .fontWeight(isSelected ? .semibold : .regular)

                    HStack(spacing: 8) {
                        Text("\(source.width)×\(source.height)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text("\(Int(source.refreshRate))Hz")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if source.isMain {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Main")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(AppColor.inset)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.3) : AppColor.inset)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct WindowSourceRow: View {
    let source: SourceSelector.WindowSource
    let isSelected: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 44, height: 30)

                    Image(systemName: "macwindow")
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(source.applicationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(AppColor.inset)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(isSelected ? Color.purple.opacity(0.3) : AppColor.inset)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ApplicationSourceRow: View {
    let source: SourceSelector.ApplicationSource
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 36, height: 36)

                    Image(systemName: "app.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(source.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.green.opacity(0.3) : AppColor.inset)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
