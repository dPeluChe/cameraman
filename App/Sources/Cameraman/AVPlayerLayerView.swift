//
//  AVPlayerLayerView.swift
//  Cameraman
//
//  NSViewRepresentable wrapping AVPlayerLayer for fluid 60fps preview.
//  Replaces the CGImage frame-by-frame extraction approach.
//

import AVFoundation
import AVKit
import SwiftUI

/// SwiftUI wrapper around AVPlayerView for native video playback
struct AVPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
