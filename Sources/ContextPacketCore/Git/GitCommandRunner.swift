import Foundation

public struct GitCommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool {
        exitCode == 0
    }
}

public enum GitError: LocalizedError, Sendable {
    case notAGitRepository(String)
    case commandFailed(command: String, exitCode: Int32, message: String)
    case processExecutionFailed(String)
    case timedOut(String)

    public var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return "The selected folder is not a Git repository: \(path)"
        case .commandFailed(let command, let exitCode, let message):
            return "Git command '\(command)' failed with code \(exitCode): \(message)"
        case .processExecutionFailed(let reason):
            return "Failed to execute Git: \(reason)"
        case .timedOut(let command):
            return "Git command timed out: \(command)"
        }
    }
}

public final class GitCommandRunner: Sendable {
    public init() {}

    public func run(
        arguments: [String],
        in workingDirectory: URL,
        timeoutSeconds: Double = 15.0
    ) async throws -> GitCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = workingDirectory

                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "C"
                environment["LANG"] = "C"
                environment["GIT_TERMINAL_PROMPT"] = "0"
                process.environment = environment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GitError.processExecutionFailed(error.localizedDescription))
                    return
                }

                // Timeout watchdog
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                var didFinish = false
                let lock = NSLock()

                timer.schedule(deadline: .now() + timeoutSeconds)
                timer.setEventHandler {
                    lock.lock()
                    defer { lock.unlock() }
                    if !didFinish && process.isRunning {
                        process.terminate()
                        didFinish = true
                        continuation.resume(throwing: GitError.timedOut(arguments.joined(separator: " ")))
                    }
                }
                timer.resume()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                timer.cancel()

                lock.lock()
                defer { lock.unlock() }
                if !didFinish {
                    didFinish = true
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(returning: GitCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            }
        }
    }
}
