import Foundation

protocol CommandRunning: Sendable {
    func run(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        timeout: TimeInterval
    ) -> SafeCommandRunner.ExecutionResult
}

struct SafeCommandRunner: CommandRunning, Sendable {
    enum Command: Sendable {
        case ps
        case vmStat
        case uptime
        case top
        case launchctl
        case spctl
        case fdesetup
        case csrutil
        case socketFilterFirewall
        case pkgutil
        case softwareupdate
        case plutil
        case brew

        var executableURL: URL {
            switch self {
            case .ps:
                return URL(fileURLWithPath: "/bin/ps")
            case .vmStat:
                return URL(fileURLWithPath: "/usr/bin/vm_stat")
            case .uptime:
                return URL(fileURLWithPath: "/usr/bin/uptime")
            case .top:
                return URL(fileURLWithPath: "/usr/bin/top")
            case .launchctl:
                return URL(fileURLWithPath: "/bin/launchctl")
            case .spctl:
                return URL(fileURLWithPath: "/usr/sbin/spctl")
            case .fdesetup:
                return URL(fileURLWithPath: "/usr/bin/fdesetup")
            case .csrutil:
                return URL(fileURLWithPath: "/usr/bin/csrutil")
            case .socketFilterFirewall:
                return URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
            case .pkgutil:
                return URL(fileURLWithPath: "/usr/sbin/pkgutil")
            case .softwareupdate:
                return URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            case .plutil:
                return URL(fileURLWithPath: "/usr/bin/plutil")
            case .brew:
                if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                    return URL(fileURLWithPath: "/opt/homebrew/bin/brew")
                }

                return URL(fileURLWithPath: "/usr/local/bin/brew")
            }
        }

        var displayName: String {
            executableURL.lastPathComponent
        }
    }

    struct ExecutionResult: Equatable, Sendable {
        enum FailureReason: Equatable, Sendable {
            case launchFailed(String)
            case timedOut(TimeInterval)
            case nonZeroExit
        }

        let command: Command
        let arguments: [String]
        let standardOutput: String
        let standardError: String
        let exitStatus: Int32
        let failureReason: FailureReason?

        var succeeded: Bool {
            exitStatus == 0 && failureReason == nil
        }
    }

    func run(
        _ command: Command,
        arguments: [String],
        timeout: TimeInterval = 5.0
    ) -> ExecutionResult {
        let stdoutURL = temporaryFileURL(suffix: "stdout")
        let stderrURL = temporaryFileURL(suffix: "stderr")

        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        guard
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil),
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        else {
            return ExecutionResult(
                command: command,
                arguments: arguments,
                standardOutput: "",
                standardError: "",
                exitStatus: -1,
                failureReason: .launchFailed("Temporary output files could not be created.")
            )
        }

        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle

        do {
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        } catch {
            return ExecutionResult(
                command: command,
                arguments: arguments,
                standardOutput: "",
                standardError: "",
                exitStatus: -1,
                failureReason: .launchFailed(error.localizedDescription)
            )
        }

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return ExecutionResult(
                command: command,
                arguments: arguments,
                standardOutput: "",
                standardError: "",
                exitStatus: -1,
                failureReason: .launchFailed(error.localizedDescription)
            )
        }

        let waitResult = terminationSemaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            if process.isRunning {
                process.terminate()
                _ = terminationSemaphore.wait(timeout: .now() + 1)
            }

            return ExecutionResult(
                command: command,
                arguments: arguments,
                standardOutput: readString(at: stdoutURL),
                standardError: readString(at: stderrURL),
                exitStatus: process.isRunning ? -1 : process.terminationStatus,
                failureReason: .timedOut(timeout)
            )
        }

        let failureReason: ExecutionResult.FailureReason? = process.terminationStatus == 0 ? nil : .nonZeroExit
        return ExecutionResult(
            command: command,
            arguments: arguments,
            standardOutput: readString(at: stdoutURL),
            standardError: readString(at: stderrURL),
            exitStatus: process.terminationStatus,
            failureReason: failureReason
        )
    }

    private func temporaryFileURL(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("machealthos-\(UUID().uuidString)-\(suffix)")
    }

    private func readString(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return ""
        }

        return String(decoding: data, as: UTF8.self)
    }
}
