//
//  TeleprompterViewModel.swift
//  App
//
//  Extracted from TeleprompterWindow.swift
//  ViewModel for teleprompter playback
//

import SwiftUI
import Combine

@MainActor
class TeleprompterViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fontSize: CGFloat = 28
    @Published var scrollSpeed: Double = 30
    @Published var isPlaying: Bool = false
    @Published var mode: TeleprompterMode = .scroll
    @Published var tab: TeleprompterTab = .edit

    @Published var scrollOffset: CGFloat = 0
    @Published var currentWordIndex: Int = 0

    @Published var currentParagraphIndex: Int = 0
    @Published var currentParagraphWordIndex: Int = 0

    @Published private(set) var words: [String] = []
    @Published private(set) var paragraphs: [String] = []
    @Published private(set) var paragraphWords: [[String]] = []

    var currentParagraphWords: [String] {
        guard currentParagraphIndex < paragraphWords.count else { return [] }
        return paragraphWords[currentParagraphIndex]
    }

    private var scrollTimer: Timer?
    private var wordTimer: Timer?

    deinit {
        scrollTimer?.invalidate()
        wordTimer?.invalidate()
    }

    func rebuildCache() {
        words = text.split(separator: " ").map(String.init)
        paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        paragraphWords = paragraphs.map { $0.split(separator: " ").map(String.init) }
    }

    func play() {
        pause()
        rebuildCache()
        isPlaying = true

        let wpm = scrollSpeed * 4
        let wordInterval = 60.0 / wpm

        if mode == .scroll {
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                guard let vm = self else { return }
                Task { @MainActor in
                    guard vm.isPlaying else { return }
                    vm.scrollOffset += CGFloat(vm.scrollSpeed / 15.0)
                }
            }
        }

        wordTimer = Timer.scheduledTimer(withTimeInterval: wordInterval, repeats: true) { [weak self] _ in
            guard let vm = self else { return }
            Task { @MainActor in
                guard vm.isPlaying else { return }
                vm.advanceWord()
            }
        }
    }

    func pause() {
        isPlaying = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        wordTimer?.invalidate()
        wordTimer = nil
    }

    func reset() {
        pause()
        scrollOffset = 0
        currentWordIndex = 0
        currentParagraphIndex = 0
        currentParagraphWordIndex = 0
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    private func advanceWord() {
        switch mode {
        case .scroll:
            if currentWordIndex < words.count - 1 {
                currentWordIndex += 1
            } else {
                pause()
            }
        case .paragraph:
            let pw = currentParagraphWords
            if currentParagraphWordIndex < pw.count - 1 {
                currentParagraphWordIndex += 1
            } else if currentParagraphIndex < paragraphWords.count - 1 {
                currentParagraphIndex += 1
                currentParagraphWordIndex = 0
            } else {
                pause()
            }
        }
    }

    func nextParagraph() {
        guard currentParagraphIndex < paragraphWords.count - 1 else { return }
        currentParagraphIndex += 1
        currentParagraphWordIndex = 0
    }

    func prevParagraph() {
        guard currentParagraphIndex > 0 else { return }
        currentParagraphIndex -= 1
        currentParagraphWordIndex = 0
    }
}
