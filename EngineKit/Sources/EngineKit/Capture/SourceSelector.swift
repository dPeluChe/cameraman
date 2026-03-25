//
//  SourceSelector.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
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
    /// - Returns: Array of WindowSource
    /// - Throws: SourceSelectorError if enumeration fails
    public func listWindows() async throws -> [WindowSource] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            var windows: [WindowSource] = []

            // Create a map of bundleIdentifier to SCRunningApplication
            var appMap: [String: SCRunningApplication] = [:]
            for app in content.applications {
                appMap[app.bundleIdentifier] = app
            }

            for window in content.windows {
                // Skip windows without titles or very small windows (likely menus, tooltips, etc.)
                guard let title = window.title, !title.isEmpty else { continue }
                guard window.frame.width > 50 && window.frame.height > 50 else { continue }

                // Get application info from the window's owning application
                let app = content.applications.first { $0.bundleIdentifier == window.owningApplication?.bundleIdentifier }

                let windowSource = WindowSource(
                    id: "\(window.windowID)",
                    title: title,
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
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            let applications = content.applications.map { application in
                ApplicationSource(
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
