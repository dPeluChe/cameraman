//
//  ProjectThumbnail.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import AppKit
import Combine
import SwiftUI

enum ProjectThumbnailProvider {
    static func loadImage(from path: String?) -> NSImage? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return NSImage(contentsOfFile: path)
    }
}

struct ProjectThumbnailView: View {
    let thumbnailPath: String?

    var body: some View {
        if let image = ProjectThumbnailProvider.loadImage(from: thumbnailPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ProjectThumbnailView(thumbnailPath: nil)
        .frame(width: 120, height: 80)
}
