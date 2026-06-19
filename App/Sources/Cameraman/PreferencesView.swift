//
//  PreferencesView.swift
//  App
//
//  Created by Ralphy on 2026-01-20
//

import SwiftUI
import EngineKit

/// Main preferences window for app configuration
struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @State private var selectedTab: PreferencesTab = .general

    private enum PreferencesTab: String, CaseIterable {
        case general = "General"
        case hotkeys = "Hotkeys"
        case recording = "Recording"
        case export = "Export"
        case transcription = "Transcription"
        case integrations = "Integrations"
        case diagnostics = "Diagnostics"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .hotkeys: return "command"
            case .recording: return "record.circle"
            case .export: return "square.and.arrow.up"
            case .transcription: return "captions.bubble"
            case .integrations: return "puzzlepiece.extension"
            case .diagnostics: return "stethoscope"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16))
                            Text(tab.rawValue)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                        // Make the whole cell clickable, not just the icon/text
                        // glyphs (Color.clear backgrounds aren't hit-testable).
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.rawValue)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        GeneralPreferencesView()
                    case .hotkeys:
                        HotkeysPreferencesView()
                    case .recording:
                        RecordingPreferencesView()
                    case .export:
                        ExportPreferencesView()
                    case .transcription:
                        TranscriptionPreferencesView()
                    case .integrations:
                        IntegrationsPreferencesView()
                    case .diagnostics:
                        DiagnosticsView()
                    case .about:
                        AboutPreferencesView()
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 650, height: 450)
    }
}

// MARK: - Preview

#Preview("Preferences Window") {
    PreferencesView()
}
