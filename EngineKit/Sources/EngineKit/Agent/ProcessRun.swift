//
//  ProcessRun.swift
//  EngineKit
//
//  Runs a child process without blocking a thread: exit is awaited through terminationHandler, and stderr
//  is drained while it runs so a chatty process cannot fill the pipe and stall.
//

import Foundation

enum ProcessRun {
    struct Result {
        let status: Int32
        let output: String
        /// The last few KB of stderr, for error messages.
        let errorTail: String
    }

    /// Runs to the end and returns everything it printed; terminated after `timeout` seconds.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var output = ""
        let deadline = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning { process.terminate() }
        }
        defer { deadline.cancel() }
        let result = try await stream(process, input: nil) { output += $0 + "\n" }
        return Result(status: result.status, output: output, errorTail: result.errorTail)
    }

    /// Starts `process`, writes `input` to its stdin (or gives it none) and calls `line` for each stdout line.
    static func stream(_ process: Process, input: Data?, line: (String) -> Void) async throws -> Result {
        let output = Pipe(), errors = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        let tail = ErrorTail()
        errors.fileHandleForReading.readabilityHandler = { tail.append($0.availableData) }
        let exited = AsyncStream<Int32> { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        try process.run()
        if let input {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        for try await text in output.fileHandleForReading.bytes.lines { line(text) }
        var status: Int32 = -1
        for await code in exited { status = code }
        errors.fileHandleForReading.readabilityHandler = nil
        return Result(status: status, output: "", errorTail: tail.text)
    }

    private final class ErrorTail: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
            if data.count > 4096 { data = data.suffix(4096) }
        }

        var text: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
