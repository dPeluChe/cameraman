//
//  SourceSelector.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import CoreGraphics
import ScreenCaptureKit

/// SourceSelector provides functionality to enumerate available capture sources
public actor SourceSelector {
    /// Errors that can occur during source selection
    public enum SourceSelectorError: Error, LocalizedError {
        case permissionDenied
        case failedToEnumerateDisplays(underlying: Error)
        case failedToEnumerateWindows(underlying: Error)
        case failedToEnumerateApplications(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screen recording permission denied"
            case .failedToEnumerateDisplays(let error):
                return "Failed to enumerate displays: \(error.localizedDescription)"
            case .failedToEnumerateWindows(let error):
                return "Failed to enumerate windows: \(error.localizedDescription)"
            case .failedToEnumerateApplications(let error):
                return "Failed to enumerate applications: \(error.localizedDescription)"
            }
        }
    }

    /// Available display sources
    public struct DisplaySource: Identifiable, Equatable {
        public let id: String
        public let name: String
        /// Physical pixel width (logical points × backingScaleFactor)
        public let width: Int
        /// Physical pixel height (logical points × backingScaleFactor)
        public let height: Int
        public let refreshRate: Double
        public let isMain: Bool
        /// Retina scale factor (1.0 for standard displays, 2.0 for Retina)
        public let backingScaleFactor: Double

        public init(id: String, name: String, width: Int, height: Int, refreshRate: Double, isMain: Bool, backingScaleFactor: Double = 1.0) {
            self.id = id
            self.name = name
            self.width = width
            self.height = height
            self.refreshRate = refreshRate
            self.isMain = isMain
            self.backingScaleFactor = backingScaleFactor
        }
    }

    /// Available window sources
    public struct WindowSource: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let applicationName: String
        public let applicationBundleIdentifier: String
        public let width: Int
        public let height: Int
        public let isOnScreen: Bool

        public init(
            id: String,
            title: String,
            applicationName: String,
            applicationBundleIdentifier: String,
            width: Int,
            height: Int,
            isOnScreen: Bool
        ) {
            self.id = id
            self.title = title
            self.applicationName = applicationName
            self.applicationBundleIdentifier = applicationBundleIdentifier
            self.width = width
            self.height = height
            self.isOnScreen = isOnScreen
        }
    }

    /// Available application sources
    public struct ApplicationSource: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let bundleIdentifier: String
        public let iconPath: String?

        public init(id: String, name: String, bundleIdentifier: String, iconPath: String?) {
            self.id = id
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.iconPath = iconPath
        }
    }

    /// Shared instance
    public static let shared = SourceSelector()

    private init() {}

    // MARK: - Display Enumeration

    /// List all available displays
    /// - Returns: Array of DisplaySource
    /// - Throws: SourceSelectorError if enumeration fails
    public func listDisplays() async throws -> [DisplaySource] {
        let screens = NSScreen.screens

        guard !screens.isEmpty else {
            return []
        }

        return screens.enumerated().map { index, screen in
            let frame = screen.frame
            let isMain = screen == NSScreen.main
            let scale = screen.backingScaleFactor

            // Try to get display name from device description
            let deviceDescription = screen.deviceDescription
            let displayName = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.description ?? "Display \(index + 1)"

            // Get refresh rate (default to 60fps if not available)
            let refreshRate = 60.0 // Could be enhanced with CGDisplayCopyDisplayConfiguration

            return DisplaySource(
                id: displayName,
                name: isMain ? "Main Display" : "Display \(index + 1)",
                // Store physical pixels (not logical points) so streamConfig gets correct dimensions
                width: Int(frame.width * scale),
                height: Int(frame.height * scale),
                refreshRate: refreshRate,
                isMain: isMain,
                backingScaleFactor: scale
            )
        }
    }

    // MARK: - Window Enumeration

    /// List all available windows
    /// A window worth offering as a capture source: real, visible, titled, not our own.
    private func isCapturableWindow(_ window: SCWindow, ownBundleID: String?) -> Bool {
        guard let title = window.title, !title.isEmpty else { return false }
        guard window.frame.width > 50 && window.frame.height > 50 else { return false }
        guard let appName = window.owningApplication?.applicationName, !appName.isEmpty else { return false }
        if let bid = window.owningApplication?.bundleIdentifier, bid == ownBundleID { return false }
        return true
    }

    /// - Returns: Array of WindowSource
    /// - Throws: SourceSelectorError if enumeration fails
    public func listWindows() async throws -> [WindowSource] {
        do {
            // excludingDesktopWindows:true drops wallpaper/desktop-icon layers;
            // onScreenWindowsOnly:true drops minimized/offscreen windows the user can't see.
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownBundleID = Bundle.main.bundleIdentifier

            var windows: [WindowSource] = []

            for window in content.windows where isCapturableWindow(window, ownBundleID: ownBundleID) {
                let app = window.owningApplication
                let windowSource = WindowSource(
                    id: "\(window.windowID)",
                    title: window.title ?? "",
                    applicationName: app?.applicationName ?? "Unknown",
                    applicationBundleIdentifier: app?.bundleIdentifier ?? "unknown",
                    width: Int(window.frame.width),
                    height: Int(window.frame.height),
                    isOnScreen: window.isOnScreen
                )
                windows.append(windowSource)
            }

            // Sort by application name and window title
            return windows.sorted { lhs, rhs in
                if lhs.applicationName == rhs.applicationName {
                    return lhs.title < rhs.title
                }
                return lhs.applicationName < rhs.applicationName
            }
        } catch let error as NSError {
            // Check for TCC permission denied error
            if error.domain.contains("SCStreamErrorDomain") && error.code == -3801 {
                throw SourceSelectorError.permissionDenied
            }
            throw SourceSelectorError.failedToEnumerateWindows(underlying: error)
        }
    }

    // MARK: - Application Enumeration

    /// List all available applications
    /// - Returns: Array of ApplicationSource
    /// - Throws: SourceSelectorError if enumeration fails
    public func listApplications() async throws -> [ApplicationSource] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownBundleID = Bundle.main.bundleIdentifier

            // Only list apps that own at least one real, visible window — otherwise the
            // list fills with background daemons/agents (empty rows) that can't be captured.
            var capturableBundleIDs = Set<String>()
            for window in content.windows where isCapturableWindow(window, ownBundleID: ownBundleID) {
                if let bid = window.owningApplication?.bundleIdentifier { capturableBundleIDs.insert(bid) }
            }

            let applications = content.applications.compactMap { application -> ApplicationSource? in
                guard !application.applicationName.isEmpty else { return nil }
                guard application.bundleIdentifier != ownBundleID else { return nil }
                guard capturableBundleIDs.contains(application.bundleIdentifier) else { return nil }
                return ApplicationSource(
                    id: "\(application.bundleIdentifier)_\(application.processID)",
                    name: application.applicationName,
                    bundleIdentifier: application.bundleIdentifier,
                    iconPath: nil
                )
            }

            // Sort by application name
            return applications.sorted { $0.name < $1.name }
        } catch let error as NSError {
            // Check for TCC permission denied error
            if error.domain.contains("SCStreamErrorDomain") && error.code == -3801 {
                throw SourceSelectorError.permissionDenied
            }
            throw SourceSelectorError.failedToEnumerateApplications(underlying: error)
        }
    }

    // MARK: - Preview Thumbnails

    /// Capture a still thumbnail of a window so the user can confirm the right source.
    /// Returns nil on macOS 13 (SCScreenshotManager is 14+) or on failure — caller falls back to an icon.
    public func captureWindowThumbnail(windowID: String, maxDimension: Int = 640) async -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let scWindow = content.windows.first(where: { String($0.windowID) == windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        return await captureThumbnail(filter: filter, sourceSize: scWindow.frame.size, maxDimension: maxDimension)
    }

    /// Capture a still thumbnail of an application's largest visible window.
    public func captureApplicationThumbnail(bundleIdentifier: String, maxDimension: Int = 640) async -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let window = content.windows
            .filter { $0.owningApplication?.bundleIdentifier == bundleIdentifier && ($0.title?.isEmpty == false) }
            .max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) })
        guard let scWindow = window else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        return await captureThumbnail(filter: filter, sourceSize: scWindow.frame.size, maxDimension: maxDimension)
    }

    /// Capture a still thumbnail of a display.
    public func captureDisplayThumbnail(displayID: String, maxDimension: Int = 640) async -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return nil }
        let scDisplay: SCDisplay?
        if let idValue = UInt32(displayID) {
            scDisplay = content.displays.first(where: { $0.displayID == idValue }) ?? content.displays.first
        } else {
            scDisplay = content.displays.first
        }
        guard let display = scDisplay else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let size = CGSize(width: display.width, height: display.height)
        return await captureThumbnail(filter: filter, sourceSize: size, maxDimension: maxDimension)
    }

    @available(macOS 14.0, *)
    private func captureThumbnail(filter: SCContentFilter, sourceSize: CGSize, maxDimension: Int) async -> CGImage? {
        let config = SCStreamConfiguration()
        let longest = max(sourceSize.width, sourceSize.height, 1)
        let scale = min(1.0, CGFloat(maxDimension) / longest)
        config.width = max(1, Int(sourceSize.width * scale))
        config.height = max(1, Int(sourceSize.height * scale))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - Permission Check

    /// Check if screen recording permission is granted
    /// - Returns: true if permission is granted
    public func checkScreenRecordingPermission() async -> Bool {
        // Check if we can access shareable content
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - NSScreen Lookup

public extension NSScreen {
    /// Find the NSScreen matching a CGDirectDisplayID string (as stored in DisplaySource.id).
    static func screen(withDisplayID displayID: String) -> NSScreen? {
        screens.first { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return String(num.uint32Value) == displayID
        }
    }
}
