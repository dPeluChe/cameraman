//
//  GlassEffect.swift
//  App
//
//  Liquid Glass (macOS 26 "Tahoe") support with graceful fallback.
//
//  The `glassEffect` SwiftUI modifier only exists in the macOS 26 SDK, so it
//  is double-gated:
//  - `#if compiler(>=6.2)` — the project still builds with older Xcode
//    versions whose SDK doesn't declare the API.
//  - `if #available(macOS 26.0, *)` — at runtime, older systems fall back to
//    the classic translucent material (NSVisualEffectView).
//

import SwiftUI

/// Runtime probe for Apple's Liquid Glass material.
enum LiquidGlass {
    /// True when the app was built with the macOS 26 SDK **and** is running
    /// on macOS 26 or later.
    static var isSupported: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

extension View {
    /// Glass background for the projects sidebar.
    ///
    /// - macOS 26+ (built with the macOS 26 SDK): system Liquid Glass behind
    ///   the list content.
    /// - macOS 13–15 (or older SDKs): classic translucent sidebar material
    ///   with behind-window blending, so the sidebar still reads as glass.
    @ViewBuilder
    func sidebarGlassBackground() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .scrollContentBackground(.hidden)
                .background {
                    Color.clear
                        .glassEffect(.regular, in: .rect)
                        .ignoresSafeArea()
                }
        } else {
            legacySidebarGlass
        }
        #else
        legacySidebarGlass
        #endif
    }

    private var legacySidebarGlass: some View {
        self
            .scrollContentBackground(.hidden)
            .background {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            }
    }
}
