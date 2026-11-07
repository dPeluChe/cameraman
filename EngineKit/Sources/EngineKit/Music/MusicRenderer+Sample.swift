//
//  MusicRenderer+Sample.swift
//  EngineKit
//
//  Short pieces to hear a style before using it, kept in Caches until ScoreKit changes.
//

import CryptoKit
import Foundation

extension MusicRenderer {
    nonisolated public static let sampleDuration: TimeInterval = 12

    public static func sample(of style: MusicStyle) async throws -> URL {
        let file = sampleDirectory.appendingPathComponent("\(style.rawValue)-\(scoreVersion).m4a")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: file.path) { return file }
        try fileManager.createDirectory(at: sampleDirectory, withIntermediateDirectories: true)
        for name in (try? fileManager.contentsOfDirectory(atPath: sampleDirectory.path)) ?? [] where !name.contains(scoreVersion) {
            try? fileManager.removeItem(at: sampleDirectory.appendingPathComponent(name))
        }
        let partial = file.deletingPathExtension().appendingPathExtension("partial.m4a")
        try await render(MusicSource(score: .style(style), options: MusicRenderOptions(duration: sampleDuration)), to: partial)
        try fileManager.moveItem(at: partial, to: file)
        return file
    }

    private static var sampleDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicSamples", isDirectory: true)
    }

    private static let scoreVersion = SHA256.hash(data: Data(ScoreKit.script.utf8)).prefix(6)
        .map { String(format: "%02x", $0) }.joined()
}
