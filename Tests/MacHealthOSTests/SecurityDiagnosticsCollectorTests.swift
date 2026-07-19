import Foundation
import Testing
@testable import MacHealthOS

@Test func collectorBuildsSecurityDiagnosticsFromCommandOutputs() async throws {
    let collector = SecurityDiagnosticsCollector(
        configuration: SecurityDiagnosticsCollector.Configuration(
            commandTimeout: 0.5,
            softwareUpdateTimeout: 0.5,
            fixedMacOSVersion: "macOS 26.6"
        ),
        commandRunner: SecurityStubCommandRunner { command, arguments, _ in
            switch command {
            case .spctl:
                return .success(command, arguments: arguments, output: "assessments enabled\n")
            case .fdesetup:
                return .success(command, arguments: arguments, output: "FileVault is On.\n")
            case .csrutil:
                return .success(command, arguments: arguments, output: "System Integrity Protection status: enabled.\n")
            case .socketFilterFirewall:
                return .success(command, arguments: arguments, output: "Firewall is enabled. (State = 1)\n")
            case .pkgutil:
                if arguments == ["--pkgs"] {
                    return .success(
                        command,
                        arguments: arguments,
                        output: """
                        com.apple.pkg.XProtectPayloads_10_15.16U4413
                        com.apple.pkg.XProtectPlistConfigData_10_15.16U4430
                        """
                    )
                }

                if arguments.last == "com.apple.pkg.XProtectPayloads_10_15.16U4413" {
                    return .success(
                        command,
                        arguments: arguments,
                        output: """
                        package-id: com.apple.pkg.XProtectPayloads_10_15.16U4413
                        version: 157.1.1770928711
                        install-time: 1771964260
                        """
                    )
                }

                return .success(
                    command,
                    arguments: arguments,
                    output: """
                    package-id: com.apple.pkg.XProtectPlistConfigData_10_15.16U4430
                    version: 5347.1.1780030305
                    install-time: 1780436260
                    """
                )
            case .softwareupdate:
                return SafeCommandRunner.ExecutionResult(
                    command: command,
                    arguments: arguments,
                    standardOutput: "Software Update Tool\n\nFinding available software\n",
                    standardError: "No new software available.\n",
                    exitStatus: 0,
                    failureReason: nil
                )
            case .ps, .vmStat, .uptime, .top, .launchctl, .plutil, .brew:
                return .failure(command, arguments: arguments, standardError: "unexpected command")
            }
        }
    )

    let result = collector.collect()

    #expect(result.diagnostics.status == .healthy)
    #expect(result.diagnostics.gatekeeperEnabled == true)
    #expect(result.diagnostics.fileVaultEnabled == true)
    #expect(result.diagnostics.systemIntegrityProtectionEnabled == true)
    #expect(result.diagnostics.firewallEnabled == true)
    #expect(result.diagnostics.macOSVersion == "macOS 26.6")
    #expect(result.diagnostics.xProtectPayload?.version == "157.1.1770928711")
    #expect(result.diagnostics.xProtectConfigData?.version == "5347.1.1780030305")
    #expect(result.diagnostics.pendingSecurityUpdatesCount == 0)
    #expect(result.diagnostics.commandFailures.isEmpty)
    #expect(result.recommendations.isEmpty)
}

@Test func collectorFlagsDisabledSecurityControlsAndVisibleUpdates() async throws {
    let collector = SecurityDiagnosticsCollector(
        configuration: SecurityDiagnosticsCollector.Configuration(
            commandTimeout: 0.5,
            softwareUpdateTimeout: 0.5,
            fixedMacOSVersion: "macOS 26.6"
        ),
        commandRunner: SecurityStubCommandRunner { command, arguments, _ in
            switch command {
            case .spctl:
                return .success(command, arguments: arguments, output: "assessments disabled\n")
            case .fdesetup:
                return .success(command, arguments: arguments, output: "FileVault is Off.\n")
            case .csrutil:
                return .success(command, arguments: arguments, output: "System Integrity Protection status: enabled.\n")
            case .socketFilterFirewall:
                return .success(command, arguments: arguments, output: "Firewall is disabled. (State = 0)\n")
            case .pkgutil:
                if arguments == ["--pkgs"] {
                    return .success(
                        command,
                        arguments: arguments,
                        output: """
                        com.apple.pkg.XProtectPayloads_10_15.16U4413
                        com.apple.pkg.XProtectPlistConfigData_10_15.16U4430
                        """
                    )
                }

                if arguments.last == "com.apple.pkg.XProtectPayloads_10_15.16U4413" {
                    return .success(
                        command,
                        arguments: arguments,
                        output: """
                        package-id: com.apple.pkg.XProtectPayloads_10_15.16U4413
                        version: 157.1.1770928711
                        install-time: 1771964260
                        """
                    )
                }

                return .success(
                    command,
                    arguments: arguments,
                    output: """
                    package-id: com.apple.pkg.XProtectPlistConfigData_10_15.16U4430
                    version: 5347.1.1780030305
                    install-time: 1780436260
                    """
                )
            case .softwareupdate:
                return .success(
                    command,
                    arguments: arguments,
                    output: """
                    Software Update Tool

                    Finding available software
                    * Label: macOS Tahoe 26.6-25G6000
                    \tTitle: macOS Tahoe 26.6, Version: 26.6, Size: 123456K, Recommended: YES,
                    """
                )
            case .ps, .vmStat, .uptime, .top, .launchctl, .plutil, .brew:
                return .failure(command, arguments: arguments, standardError: "unexpected command")
            }
        }
    )

    let result = collector.collect()

    #expect(result.diagnostics.status == .critical)
    #expect(result.diagnostics.pendingSecurityUpdatesCount == 1)
    #expect(result.diagnostics.availableSecurityUpdateLabels == ["macOS Tahoe 26.6-25G6000"])
    #expect(result.diagnostics.issues.contains { $0.title == "FileVault is disabled" })
    #expect(result.diagnostics.issues.contains { $0.title == "Gatekeeper appears to be disabled" })
    #expect(result.diagnostics.issues.contains { $0.title == "Firewall appears to be disabled" })
    #expect(result.diagnostics.issues.contains { $0.title == "Software updates are available" })
    #expect(result.recommendations.contains { $0.title == "Review FileVault in Privacy & Security" })
    #expect(result.recommendations.contains { $0.title == "Review Software Update in System Settings" })
}

@Test func collectorMarksUnavailableSecurityDataUnknown() async throws {
    let collector = SecurityDiagnosticsCollector(
        configuration: SecurityDiagnosticsCollector.Configuration(
            commandTimeout: 0.5,
            softwareUpdateTimeout: 0.5,
            fixedMacOSVersion: "macOS 26.6"
        ),
        commandRunner: SecurityStubCommandRunner { command, arguments, _ in
            .failure(command, arguments: arguments, standardError: "permission denied")
        }
    )

    let result = collector.collect()

    #expect(result.diagnostics.status == .unknown)
    #expect(result.diagnostics.commandFailures.count == 6)
    #expect(result.diagnostics.gatekeeperEnabled == nil)
    #expect(result.diagnostics.xProtectPayload == nil)
    #expect(result.diagnostics.pendingSecurityUpdatesCount == nil)
    #expect(result.diagnostics.issues.contains { $0.title == "Some security metrics are unavailable" })
    #expect(result.diagnostics.issues.contains { $0.title == "Some security commands failed" })
    #expect(result.recommendations.contains { $0.title == "Review incomplete security visibility" })
}

private struct SecurityStubCommandRunner: CommandRunning {
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
