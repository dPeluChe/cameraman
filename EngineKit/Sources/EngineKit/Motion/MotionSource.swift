//
//  MotionSource.swift
//  EngineKit
//
//  What a motion was rendered from, kept next to its video so it can be changed and re-rendered.
//

import Foundation

public struct MotionSource: RenderSource, Equatable, Sendable {
    public static let kind = RenderedAssets.Kind.motion

    public var template: String?
    public var html: String?
    public var title = ""
    public var subtitle = ""
    public var value = ""
    public var labels: [String] = []
    public var values: [Double] = []
    public var colorHex = "#0A84FF"
    public var duration: TimeInterval?

    public init() {}
}
