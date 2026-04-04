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
    let duration: TimeInterval
    
    @State private var isVisible = false
    
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
        .scaleEffect(isVisible ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.easeOut(duration: 0.2)) {
                    isVisible = false
                }
            }
        }
    }
}

struct ToastModifier: ViewModifier {
    let message: String
    let icon: String
    let duration: TimeInterval
    
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ToastView(message: message, icon: icon, duration: duration)
                .padding(.bottom, 60)
        }
    }
}

extension View {
    func toast(message: String, icon: String = "checkmark.circle.fill", duration: TimeInterval = 2.0) -> some View {
        modifier(ToastModifier(message: message, icon: icon, duration: duration))
    }
}
