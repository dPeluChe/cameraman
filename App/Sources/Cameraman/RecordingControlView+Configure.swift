//
//  RecordingControlView+Configure.swift
//  App
//
//  Extracted from RecordingControlView.swift
//  Quality and capture area configuration rows
//

import SwiftUI
import EngineKit

struct RecordingQualityRow: View {
    @Binding var recordingQuality: RecordingQuality
    
    private let qualityOptions = RecordingQuality.allCases
    
    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .frame(width: 22)

            Text("Quality")
                .font(.system(size: 13))

            Spacer()

            Picker("", selection: $recordingQuality) {
                ForEach(qualityOptions, id: \.self) { q in
                    Text(q.rawValue).tag(q)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }
}

struct CaptureAreaRow: View {
    @Binding var selectedArea: CGRect?
    let selectedDisplaySource: SourceSelector.DisplaySource?
    let onAreaSelected: (CGRect?) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "crop")
                .font(.system(size: 14))
                .frame(width: 22)

            if let area = selectedArea {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Area")
                        .font(.system(size: 13))
                    Text("\(Int(area.width)) × \(Int(area.height))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Capture Area")
                    .font(.system(size: 13))
            }

            Spacer()

            if selectedArea != nil {
                Button {
                    onAreaSelected(nil)
                    AreaHighlightController.shared.hide()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(selectedArea == nil ? "Select" : "Change") {
                if let displaySource = selectedDisplaySource {
                    ScreenAreaSelectorController.shared.show(for: displaySource) { rect in
                        onAreaSelected(rect)
                        if let rect {
                            AreaHighlightController.shared.show(rect: rect, on: displaySource)
                        }
                    }
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
