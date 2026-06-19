//
//  Clipboard.swift
//  App
//
//  Single helper for the repeated clear-then-set NSPasteboard string copy.
//

import AppKit

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
