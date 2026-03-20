//
//  PiPMaskShape.swift
//  EngineKit
//
//  Shape types for camera PiP mask
//

import Foundation

/// Shape types for camera PiP mask
public enum PiPMaskShape: String, Codable, Equatable, CaseIterable, Sendable {
    case none           // No mask (rectangular)
    case circle         // Circular crop
    case roundedRect    // Rounded rectangle
    case capsule        // Pill shape (fully rounded ends)
}
