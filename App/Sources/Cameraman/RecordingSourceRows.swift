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

