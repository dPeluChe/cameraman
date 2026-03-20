//
//  PiPLayoutHelper.swift
//  App
//
//  Created by Ralphy on 2026-01-24.
//

import EngineKit
import Foundation

enum PiPHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

enum PiPPreset: String, CaseIterable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
}

struct PiPLayoutHelper {
    static let minimumSize: Double = 0.12
    static let defaultMargin: Double = 0.04

    static func moved(
        camera: Project.Canvas.Layout.CameraPosition,
        deltaX: Double,
        deltaY: Double
    ) -> Project.Canvas.Layout.CameraPosition {
        let x = clamp(camera.x + deltaX, min: 0, max: 1 - camera.w)
        let y = clamp(camera.y + deltaY, min: 0, max: 1 - camera.h)
        return Project.Canvas.Layout.CameraPosition(
            x: x,
            y: y,
            w: camera.w,
            h: camera.h,
            cornerRadius: camera.cornerRadius,
            maskShape: camera.maskShape
        )
    }

    static func resized(
        camera: Project.Canvas.Layout.CameraPosition,
        handle: PiPHandle,
        deltaX: Double,
        deltaY: Double,
        minimumSize: Double = PiPLayoutHelper.minimumSize
    ) -> Project.Canvas.Layout.CameraPosition {
        var x = camera.x
        var y = camera.y
        var w = camera.w
        var h = camera.h

        switch handle {
        case .topLeft:
            let newX = clamp(camera.x + deltaX, min: 0, max: camera.x + camera.w - minimumSize)
            let newY = clamp(camera.y + deltaY, min: 0, max: camera.y + camera.h - minimumSize)
            w = camera.w + (camera.x - newX)
            h = camera.h + (camera.y - newY)
            x = newX
            y = newY
        case .topRight:
            let newY = clamp(camera.y + deltaY, min: 0, max: camera.y + camera.h - minimumSize)
            w = clamp(camera.w + deltaX, min: minimumSize, max: 1 - camera.x)
            h = camera.h + (camera.y - newY)
            y = newY
        case .bottomLeft:
            let newX = clamp(camera.x + deltaX, min: 0, max: camera.x + camera.w - minimumSize)
            w = camera.w + (camera.x - newX)
            h = clamp(camera.h + deltaY, min: minimumSize, max: 1 - camera.y)
            x = newX
        case .bottomRight:
            w = clamp(camera.w + deltaX, min: minimumSize, max: 1 - camera.x)
            h = clamp(camera.h + deltaY, min: minimumSize, max: 1 - camera.y)
        }

        return Project.Canvas.Layout.CameraPosition(
            x: clamp(x, min: 0, max: 1 - w),
            y: clamp(y, min: 0, max: 1 - h),
            w: w,
            h: h,
            cornerRadius: camera.cornerRadius,
            maskShape: camera.maskShape
        )
    }

    static func presetPosition(
        _ preset: PiPPreset,
        camera: Project.Canvas.Layout.CameraPosition,
        margin: Double = PiPLayoutHelper.defaultMargin
    ) -> Project.Canvas.Layout.CameraPosition {
        let clampedMargin = max(0, margin)
        let x: Double
        let y: Double

        switch preset {
        case .topLeft:
            x = clampedMargin
            y = clampedMargin
        case .topRight:
            x = 1 - camera.w - clampedMargin
            y = clampedMargin
        case .bottomLeft:
            x = clampedMargin
            y = 1 - camera.h - clampedMargin
        case .bottomRight:
            x = 1 - camera.w - clampedMargin
            y = 1 - camera.h - clampedMargin
        }

        return Project.Canvas.Layout.CameraPosition(
            x: clamp(x, min: 0, max: 1 - camera.w),
            y: clamp(y, min: 0, max: 1 - camera.h),
            w: camera.w,
            h: camera.h,
            cornerRadius: camera.cornerRadius,
            maskShape: camera.maskShape
        )
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        guard min <= max else { return min }
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
