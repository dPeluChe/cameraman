//
//  EngineContext.swift
//  EngineKit
//
//  Context for dependency injection - groups core engine instances
//

import Foundation

/// EngineContext provides a way to inject engine dependencies instead of using singletons.
/// This enables:
/// - Testing with mock implementations
/// - Multiple recording sessions in parallel
/// - Better separation of concerns
///
/// ## Usage
///
/// Instead of using singletons:
/// ```swift
/// let recorder = Recorder.shared  // Uses CaptureEngine.shared internally
/// ```
///
/// Use dependency injection:
/// ```swift
/// let context = EngineContext()
/// let recorder = Recorder(
///     captureEngine: context.captureEngine,
///     cameraEngine: context.cameraEngine
/// )
/// ```
public struct EngineContext: Sendable {
    /// Screen/audio capture engine
    public let captureEngine: CaptureEngine
    
    /// Camera capture engine
    public let cameraEngine: CameraEngine
    
    /// Permission manager
    public let permissionManager: PermissionManager
    
    /// Project library
    public let projectLibrary: ProjectLibrary
    
    /// Telemetry recorder (created per-session, not shared)
    public let makeTelemetryRecorder: @Sendable () -> TelemetryRecorder
    
    public init(
        captureEngine: CaptureEngine = .shared,
        cameraEngine: CameraEngine = .shared,
        permissionManager: PermissionManager = .shared,
        projectLibrary: ProjectLibrary = .shared,
        makeTelemetryRecorder: @Sendable @escaping () -> TelemetryRecorder = { TelemetryRecorder() }
    ) {
        self.captureEngine = captureEngine
        self.cameraEngine = cameraEngine
        self.permissionManager = permissionManager
        self.projectLibrary = projectLibrary
        self.makeTelemetryRecorder = makeTelemetryRecorder
    }
    
    /// Default shared context using all singletons
    public static let shared = EngineContext()
}