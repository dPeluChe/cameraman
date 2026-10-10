//
//  Project+CameraAccessories.swift
//  EngineKit
//
//  Props drawn on the camera layer: built-in ones that follow the face (glasses, hat) and the
//  user's own images (a logo, a sticker) pinned to the face or to the camera frame.
//

import Foundation

extension Project {
    /// An image (SVG, PNG, JPG) the user added, stored in the project's `assets/` folder.
    public struct CustomAccessory: Codable, Equatable, Identifiable, Sendable {
        public enum Anchor: String, Codable, CaseIterable, Sendable {
            // Follow the face (nothing is drawn on a frame without one).
            case headTop, eyes
            // Pinned to the camera frame, no face needed.
            case topLeft, topCenter, topRight, center, bottomLeft, bottomCenter, bottomRight

            /// Where on the camera frame the image is pinned, as (x, y) in 0...1 from the bottom-left. Nil
            /// for the face anchors, which follow the face instead.
            public var framePivot: CGPoint? {
                switch self {
                case .headTop, .eyes: return nil
                case .topLeft: return CGPoint(x: 0, y: 1)
                case .topCenter: return CGPoint(x: 0.5, y: 1)
                case .topRight: return CGPoint(x: 1, y: 1)
                case .center: return CGPoint(x: 0.5, y: 0.5)
                case .bottomLeft: return CGPoint(x: 0, y: 0)
                case .bottomCenter: return CGPoint(x: 0.5, y: 0)
                case .bottomRight: return CGPoint(x: 1, y: 0)
                }
            }

            public var followsFace: Bool { framePivot == nil }
        }

        public var id: UUID
        public var name: String
        /// Project-relative, e.g. "assets/logo.svg".
        public var assetPath: String
        public var anchor: Anchor
        /// Width as a fraction of the face width (face anchors) or of the camera frame (frame anchors).
        public var size: Double
        /// Nudge from the anchor, as a fraction of the frame width / height (right and up are positive).
        public var offsetX: Double
        public var offsetY: Double
        public var opacity: Double

        public static let sizeRange: ClosedRange<Double> = 0.05...1.5

        public init(id: UUID = UUID(), name: String, assetPath: String, anchor: Anchor = .bottomCenter,
                    size: Double = 0.3, offsetX: Double = 0, offsetY: Double = 0, opacity: Double = 1) {
            self.id = id
            self.name = name
            self.assetPath = assetPath
            self.anchor = anchor
            self.size = size
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.opacity = opacity
        }

        /// A face sticker is about face-sized; a corner logo is a smaller share of the frame.
        public static func defaultSize(for anchor: Anchor) -> Double { anchor.followsFace ? 0.9 : 0.3 }

        /// Moving the image to another kind of anchor also resets its size to that anchor's natural one.
        public mutating func setAnchor(_ newAnchor: Anchor) {
            anchor = newAnchor
            size = Self.defaultSize(for: newAnchor)
        }
    }

    public struct CameraAccessories: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case glasses
            case sunglasses
            case partyHat
            case crown
        }

        /// Built-in props, drawn in this order, later ones on top.
        public var kinds: [Kind]
        /// 1 fits the face; the slider range is `scaleRange`. Applies to the built-in props.
        public var scale: Double
        /// The user's own images, drawn after the built-in props.
        public var custom: [CustomAccessory]

        public static let scaleRange: ClosedRange<Double> = 0.6...1.6

        public init(kinds: [Kind] = [], scale: Double = 1, custom: [CustomAccessory] = []) {
            self.kinds = kinds
            self.scale = scale
            self.custom = custom
        }

        enum CodingKeys: String, CodingKey { case kinds, scale, custom }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kinds = try container.decodeIfPresent([Kind].self, forKey: .kinds) ?? []
            scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
            custom = try container.decodeIfPresent([CustomAccessory].self, forKey: .custom) ?? []
        }

        public var hasBuiltIns: Bool { !kinds.isEmpty }

        /// Anything to draw at all.
        public var isActive: Bool { hasBuiltIns || !custom.isEmpty }

        /// Whether any piece needs a face found in the frame (frame-pinned logos do not).
        public var needsFace: Bool { hasBuiltIns || custom.contains { $0.anchor.followsFace } }

        public mutating func toggle(_ kind: Kind) {
            if let index = kinds.firstIndex(of: kind) { kinds.remove(at: index) } else { kinds.append(kind) }
        }
    }
}

extension Project {
    /// A copy whose custom accessory paths are absolute, for code that has no project directory at hand.
    func resolvingAccessoryPaths(in directory: URL) -> Project {
        var copy = self
        for index in copy.cameraAccessories.custom.indices where !copy.cameraAccessories.custom[index].assetPath.hasPrefix("/") {
            copy.cameraAccessories.custom[index].assetPath = directory.appendingPathComponent(copy.cameraAccessories.custom[index].assetPath).path
        }
        return copy
    }
}

extension Project {
    /// Background change or accessories on the camera layer: only the custom compositor can draw them,
    /// so the composition builders must not take their plain-layer shortcut.
    var hasCameraEffects: Bool { cameraBackground.isActive || cameraAccessories.isActive }
}
