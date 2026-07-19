import Foundation
import Testing
@testable import MacHealthOS

@Test func collectorBuildsPerformanceDiagnosticsFromCommandOutputs() async throws {
    let collector = PerformanceDiagnosticsCollector(
        configuration: PerformanceDiagnosticsCollector.Configuration(
            commandTimeout: 0.5,
            maximumReportedProcesses: 3,
            maximumReportedServiceLabels: 6,
            fixedPhysicalMemoryBytes: 16 * 1_073_741_824,
            fixedUptimeSeconds: 3 * 3_600 + 40 * 60,
            userID: 501
        ),
        commandRunner: StubCommandRunner { command, arguments, _ in
            switch command {
            case .top:
                return .success(
                    command,
                    arguments: arguments,
                    output: """
                    Processes: 868 total, 6 running, 862 sleeping, 4365 threads
                    2026/06/25 20:03:22
                    Load Avg: 6.37, 5.00, 3.84
                    CPU usage: 25.99% user, 16.59% sys, 57.41% idle
                    PhysMem: 15G used (2309M wired, 3791M compressor), 394M unused.
                    """
                )
            case .vmStat:
                return .success(
                    command,
                    arguments: arguments,
                    output: """
                    Mach Virtual Memory Statistics: (page size of 16384 bytes)
                    Pages free:                                     9774.
                    Pages active:                                 306516.
                    Pages inactive:                               296234.
                    Pages speculative:                              9333.
                    Pages purgeable:                               10440.
                    Pages occupied by compressor:                 240338.
                    Pageouts:                                      39786.
                    """
                )
            case .ps:
                if arguments.contains("pid=,pcpu=,pmem=,rss=,comm=") {
                    return .success(
                        command,
                        arguments: arguments,
                        output: """
                          169  44.6  0.6 106080 WindowServer
                          735  30.5  0.7 125424 Codex (Service)
                          858  13.8  2.4 409216 Codex (Renderer)
                        """
                    )
                }

                return .success(
                    command,
                    arguments: arguments,
                    output: """
                      858  2.4 409216  13.8 Codex (Renderer)
                      798  1.1 187440   3.8 codex
                      735  0.7 125424  30.5 Codex (Service)
                    """
                )
            case .launchctl:
                return .success(
                    command,
                    arguments: arguments,
                    output: """
                    gui/501 = {
                        service count = 464
                        active service count = 254

                        disabled services = {
                            "com.apple.ManagedClientAgent.enrollagent" => disabled
                            "com.ollama.ollama" => enabled
                            "com.personallifeos.dashboard" => enabled
                            "io.tailscale.ipn.macos.login-item-helper" => enabled
                            "homebrew.mxcl.postgresql@16" => enabled
                            "com.asmvik.yabai" => enabled
                            "com.openai.chat-helper" => enabled
                        }
                    }
                    """
                )
            case .uptime:
                return .success(command, arguments: arguments, output: "")
            case .spctl, .fdesetup, .csrutil, .socketFilterFirewall, .pkgutil, .softwareupdate, .plutil, .brew:
                return .failure(command, arguments: arguments, standardError: "unexpected command")
            }
        }
    )

    let result = collector.collect()

    #expect(result.diagnostics.status == .warning)
    #expect(result.diagnostics.cpuLoadPercent.map { abs($0 - 42.58) < 0.1 } == true)
    #expect(result.diagnostics.memoryPressureSummary?.contains("Warning") == true)
    #expect(result.diagnostics.topCPUProcesses.first?.command == "WindowServer")
    #expect(result.diagnostics.topMemoryProcesses.first?.command == "Codex (Renderer)")
    #expect(result.diagnostics.backgroundServiceCount == 464)
    #expect(result.diagnostics.activeBackgroundServiceCount == 254)
    #expect(result.diagnostics.enabledUserServiceLabels.contains("com.asmvik.yabai"))
    #expect(result.diagnostics.accessibleLoginItemLabels == ["io.tailscale.ipn.macos.login-item-helper"])
    #expect(result.recommendations.contains { $0.title == "Review memory-heavy apps" })
}

@Test func collectorMarksUnavailableDataWhenCommandsFail() async throws {
    let collector = PerformanceDiagnosticsCollector(
        configuration: PerformanceDiagnosticsCollector.Configuration(
            commandTimeout: 0.5,
            maximumReportedProcesses: 3,
            maximumReportedServiceLabels: 3,
            fixedPhysicalMemoryBytes: 16 * 1_073_741_824,
            fixedUptimeSeconds: 86_400,
            userID: 501
        ),
        commandRunner: StubCommandRunner { command, arguments, _ in
            .failure(
                command,
                arguments: arguments,
                standardError: "permission denied"
            )
        }
    )

    let result = collector.collect()

    #expect(result.diagnostics.status == .unknown)
    #expect(result.diagnostics.commandFailures.count == 5)
    #expect(result.diagnostics.memoryPressureSummary == nil)
    #expect(result.diagnostics.topCPUProcesses.isEmpty)
    #expect(result.diagnostics.topMemoryProcesses.isEmpty)
    #expect(result.diagnostics.issues.contains { $0.title == "Some performance metrics are unavailable" })
    #expect(result.diagnostics.issues.contains { $0.title == "Some performance commands failed" })
    #expect(result.recommendations.contains { $0.title == "Review incomplete performance scan" })
}

private struct StubCommandRunner: CommandRunning {
    let handler: @Sendable (SafeCommandRunner.Command, [String], TimeInterval) -> SafeCommandRunner.ExecutionResult

    func run(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        timeout: TimeInterval
    ) -> SafeCommandRunner.ExecutionResult {
        handler(command, arguments, timeout)
    }
}

private extension SafeCommandRunner.ExecutionResult {
    static func success(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        output: String
    ) -> SafeCommandRunner.ExecutionResult {
        SafeCommandRunner.ExecutionResult(
            command: command,
            arguments: arguments,
            standardOutput: output,
            standardError: "",
            exitStatus: 0,
            failureReason: nil
        )
    }

    static func failure(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        standardError: String
    ) -> SafeCommandRunner.ExecutionResult {
        SafeCommandRunner.ExecutionResult(
            command: command,
            arguments: arguments,
            standardOutput: "",
            standardError: standardError,
            exitStatus: 1,
            failureReason: .nonZeroExit
        )
    }
}
