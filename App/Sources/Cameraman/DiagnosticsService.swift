//
//  DiagnosticsService.swift
//  App
//
//  Builds a human-readable diagnostics report (env + permissions + logs + crashes)
//  for in-app bug reporting. No Terminal required by the user.
//

import Foundation
import EngineKit

enum DiagnosticsService {

    // MARK: - System info

    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }
    static var deviceModel: String { sysctl("hw.model") ?? "Unknown" }
    static var architecture: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        return machine.isEmpty ? "Unknown" : machine
    }

    private static func sysctl(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Permissions

    static func permissionLines() async -> [(label: String, status: String, ok: Bool)] {
        let health = await PermissionManager.shared.performHealthCheck()
        func name(_ s: PermissionManager.PermissionStatus) -> String {
            switch s {
            case .authorized: return "authorized"
            case .denied: return "denied"
            case .notDetermined: return "not determined"
            }
        }
        return [
            ("Screen Recording", name(health.screenRecording), health.screenRecording == .authorized),
            ("Microphone", name(health.microphone), health.microphone == .authorized),
            ("Camera", name(health.camera), health.camera == .authorized),
        ]
    }

    // MARK: - Report

    /// Build the full plain-text report.
    static func buildReport(logLimit: Int = 300) async -> String {
        let formatter = ISO8601DateFormatter()
        var out = "Cameraman Diagnostics Report\n"
        out += "Generated: \(formatter.string(from: Date()))\n\n"

        out += "== App ==\n"
        out += "Version: \(appVersion)\n"
        out += "macOS: \(osVersion)\n"
        out += "Model: \(deviceModel)\n"
        out += "Arch: \(architecture)\n\n"

        out += "== Permissions ==\n"
        for line in await permissionLines() {
            out += "\(line.label): \(line.status)\(line.ok ? "" : "   <-- needs attention")\n"
        }
        out += "\n"

        let crashes = await CrashReporter.shared.getRecentCrashReports(limit: 5)
        out += "== Recent Crashes (\(crashes.count)) ==\n"
        if crashes.isEmpty {
            out += "None\n"
        } else {
            for c in crashes {
                out += "[\(formatter.string(from: c.timestamp))] \(c.crashType.rawValue): \(c.reason)\n"
                if let trace = c.stackTrace, !trace.isEmpty {
                    out += trace.split(separator: "\n").prefix(12).joined(separator: "\n") + "\n"
                }
            }
        }
        out += "\n"

        let logs = await LoggingSystem.shared.getRecentLogs(limit: logLimit)
        out += "== Recent Logs (\(logs.count)) ==\n"
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss.SSS"
        for entry in logs {
            out += "\(time.string(from: entry.timestamp)) [\(levelName(entry.level))] [\(entry.category.rawValue)] \(entry.message)\n"
        }
        return out
    }

    private static func levelName(_ level: LoggingSystem.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }

    /// True if a crash report was written since the last recorded launch (used to
    /// proactively offer a report after a crash).
    static func crashedSinceLastLaunch() async -> Bool {
        let key = "diagnostics.lastLaunchDate"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key) as? Date
        defaults.set(Date(), forKey: key)
        guard let previous else { return false }
        let crashes = await CrashReporter.shared.getRecentCrashReports(limit: 5)
        return crashes.contains { $0.timestamp > previous }
    }
}
