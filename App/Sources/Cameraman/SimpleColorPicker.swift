//
//  SimpleColorPicker.swift
//  App
//
//  A short grid of preset swatches instead of the full system color panel.
//

import SwiftUI

struct SimpleColorPicker: View {
    @Binding var hex: String

    static let palette = ["#FFFFFF", "#000000", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE"]

    private let columns = Array(repeating: GridItem(.fixed(18), spacing: 5), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(Self.palette, id: \.self) { swatch in
                Button { hex = swatch } label: {
                    Circle()
                        .fill(Color(hex: swatch))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 0.5))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: isSelected(swatch) ? 2 : 0).padding(-2))
                }
                .buttonStyle(.plain)
                .help(swatch)
            }
        }
    }

    private func isSelected(_ swatch: String) -> Bool {
        hex.caseInsensitiveCompare(swatch) == .orderedSame
    }
}
