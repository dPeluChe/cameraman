//
//  ViewCompatibility.swift
//  App
//
//  Compatibility helpers for SwiftUI APIs with macOS-version-specific
//  availability.
//

import SwiftUI

extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChangeLegacy(of: value, perform: action)
        }
    }

    @available(macOS, introduced: 10.15, deprecated: 14.0)
    private func onChangeLegacy<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        onChange(of: value, perform: action)
    }
}
