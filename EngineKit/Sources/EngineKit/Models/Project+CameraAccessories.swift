//
//  Project+CameraAccessories.swift
//  EngineKit
//
//  Props drawn on the person in the camera layer (glasses, hat), anchored to the face.
//

import Foundation

extension Project {
    public struct CameraAccessories: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case glasses
            case sunglasses
            case partyHat
            case crown
        }

        /// Drawn in this order, later ones on top.
        public var kinds: [Kind]
        /// 1 fits the face; the slider range is `scaleRange`.
        public var scale: Double

        public static let scaleRange: ClosedRange<Double> = 0.6...1.6

        public init(kinds: [Kind] = [], scale: Double = 1) {
            self.kinds = kinds
            self.scale = scale
        }

        public var isActive: Bool { !kinds.isEmpty }

        public mutating func toggle(_ kind: Kind) {
            if let index = kinds.firstIndex(of: kind) { kinds.remove(at: index) } else { kinds.append(kind) }
        }
    }
}
