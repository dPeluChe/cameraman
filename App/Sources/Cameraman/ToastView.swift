//
//  ToastView.swift
//  App
//
//  Simple toast notification for brief messages
//

import SwiftUI

struct ToastView: View {
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))

            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let icon: String
    let duration: TimeInterval

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isVisible {
                ToastView(message: message, icon: icon)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 60)
            }
        }
        .onChange(of: isPresented) { _, show in
            if show {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isVisible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                    isPresented = false
                }
            }
        }
    }
}

extension View {
    func toast(_ isPresented: Binding<Bool>, message: String, icon: String = "checkmark.circle.fill", duration: TimeInterval = 1.5) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, icon: icon, duration: duration))
    }
}
