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
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .hotkeys: return "command"
            case .recording: return "record.circle"
            case .export: return "square.and.arrow.up"
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        .overlay(
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2),
                            alignment: .bottom
                        )
                    }
                    .buttonStyle(.plain)
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
