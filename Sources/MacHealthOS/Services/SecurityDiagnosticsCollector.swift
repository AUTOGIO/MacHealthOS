import Foundation

struct SecurityDiagnosticsCollector: Sendable {
    struct Configuration: Sendable {
        var commandTimeout: TimeInterval
        var softwareUpdateTimeout: TimeInterval
        var fixedMacOSVersion: String?

        init(
            commandTimeout: TimeInterval = 5.0,
            softwareUpdateTimeout: TimeInterval = 15.0,
            fixedMacOSVersion: String? = nil
        ) {
            self.commandTimeout = commandTimeout
            self.softwareUpdateTimeout = softwareUpdateTimeout
            self.fixedMacOSVersion = fixedMacOSVersion
        }
    }

    struct CollectionResult: Equatable, Sendable {
        let diagnostics: SecurityDiagnostics
        let recommendations: [MaintenanceRecommendation]
    }

    private enum Thresholds {
        static let warningSecurityUpdateCount = 1
    }

    let configuration: Configuration
    private let commandRunner: any CommandRunning

    init(
        configuration: Configuration = Configuration(),
        commandRunner: any CommandRunning = SafeCommandRunner()
    ) {
        self.configuration = configuration
        self.commandRunner = commandRunner
    }

    func collect() -> CollectionResult {
        var commandFailures: [SecurityDiagnostics.CommandFailure] = []

        let gatekeeperEnabled = collectBooleanStatus(
            command: .spctl,
            arguments: ["--status"],
            timeout: configuration.commandTimeout,
            parser: parseGatekeeperStatus(from:),
            commandFailures: &commandFailures
        )
        let fileVaultEnabled = collectBooleanStatus(
            command: .fdesetup,
            arguments: ["status"],
            timeout: configuration.commandTimeout,
            parser: parseFileVaultStatus(from:),
            commandFailures: &commandFailures
        )
        let sipEnabled = collectBooleanStatus(
            command: .csrutil,
            arguments: ["status"],
            timeout: configuration.commandTimeout,
            parser: parseSIPStatus(from:),
            commandFailures: &commandFailures
        )
        let firewallEnabled = collectBooleanStatus(
            command: .socketFilterFirewall,
            arguments: ["--getglobalstate"],
            timeout: configuration.commandTimeout,
            parser: parseFirewallStatus(from:),
            commandFailures: &commandFailures
        )

        let macOSVersion = configuration.fixedMacOSVersion ?? currentMacOSVersion()
        let packageIdentifiers = collectPackageIdentifiers(commandFailures: &commandFailures)
        let xProtectPayload = collectPackageReceipt(
            matchingPrefix: "com.apple.pkg.XProtectPayloads_",
            packageIdentifiers: packageIdentifiers,
            commandFailures: &commandFailures
        )
        let xProtectConfigData = collectPackageReceipt(
            matchingPrefix: "com.apple.pkg.XProtectPlistConfigData_",
            packageIdentifiers: packageIdentifiers,
            commandFailures: &commandFailures
        )
        let softwareUpdateInfo = collectSoftwareUpdateInfo(commandFailures: &commandFailures)

        var diagnostics = SecurityDiagnostics(
            status: .unknown,
            gatekeeperEnabled: gatekeeperEnabled,
            fileVaultEnabled: fileVaultEnabled,
            systemIntegrityProtectionEnabled: sipEnabled,
            firewallEnabled: firewallEnabled,
            macOSVersion: macOSVersion,
            xProtectPayload: xProtectPayload,
            xProtectConfigData: xProtectConfigData,
            pendingSecurityUpdatesCount: softwareUpdateInfo?.count,
            availableSecurityUpdateLabels: softwareUpdateInfo?.labels ?? [],
            commandFailures: commandFailures,
            issues: []
        )

        let issues = securityIssues(for: diagnostics)
        diagnostics.status = securityStatus(from: issues)
        diagnostics.issues = issues

        return CollectionResult(
            diagnostics: diagnostics,
            recommendations: securityRecommendations(for: diagnostics)
        )
    }

    private func collectBooleanStatus(
        command: SafeCommandRunner.Command,
        arguments: [String],
        timeout: TimeInterval,
        parser: (String) -> Bool?,
        commandFailures: inout [SecurityDiagnostics.CommandFailure]
    ) -> Bool? {
        let result = commandRunner.run(command, arguments: arguments, timeout: timeout)
        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return nil
        }

        return parser(combinedOutput(from: result))
    }

    private func collectPackageIdentifiers(
        commandFailures: inout [SecurityDiagnostics.CommandFailure]
    ) -> [String]? {
        let result = commandRunner.run(
            .pkgutil,
            arguments: ["--pkgs"],
            timeout: configuration.commandTimeout
        )

        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return nil
        }

        let packages = combinedOutput(from: result)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return packages.isEmpty ? nil : packages
    }

    private func collectPackageReceipt(
        matchingPrefix prefix: String,
        packageIdentifiers: [String]?,
        commandFailures: inout [SecurityDiagnostics.CommandFailure]
    ) -> SecurityDiagnostics.PackageReceipt? {
        guard
            let packageIdentifiers,
            let packageIdentifier = latestPackageIdentifier(matchingPrefix: prefix, packageIdentifiers: packageIdentifiers)
        else {
            return nil
        }

        let result = commandRunner.run(
            .pkgutil,
            arguments: ["--pkg-info", packageIdentifier],
            timeout: configuration.commandTimeout
        )

        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return nil
        }

        return parsePackageReceipt(combinedOutput(from: result))
    }

    private func collectSoftwareUpdateInfo(
        commandFailures: inout [SecurityDiagnostics.CommandFailure]
    ) -> (count: Int, labels: [String])? {
        let result = commandRunner.run(
            .softwareupdate,
            arguments: ["--list"],
            timeout: configuration.softwareUpdateTimeout
        )

        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return nil
        }

        return parseSoftwareUpdateInfo(combinedOutput(from: result))
    }

    private func securityIssues(for diagnostics: SecurityDiagnostics) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        let unavailableMetrics = unavailableMetricNames(diagnostics: diagnostics)
        if !unavailableMetrics.isEmpty {
            issues.append(
                HealthIssue(
                    category: .security,
                    status: .unknown,
                    title: "Some security metrics are unavailable",
                    explanation: "Unavailable metrics: \(unavailableMetrics.joined(separator: ", "))."
                )
            )
        }

        if !diagnostics.commandFailures.isEmpty {
            let failedCommands = diagnostics.commandFailures
                .prefix(3)
                .map(\.command)
                .joined(separator: ", ")
            issues.append(
                HealthIssue(
                    category: .security,
                    status: .unknown,
                    title: "Some security commands failed",
                    explanation: "Failed commands: \(failedCommands). See command notes for details."
                )
            )
        }

        if diagnostics.gatekeeperEnabled == false {
            issues.append(
                HealthIssue(
                    category: .security,
                    status: .warning,
                    title: "Gatekeeper appears to be disabled",
                    explanation: "spctl reported assessments disabled."
                )
            )
        }

        if diagnostics.fileVaultEnabled == false {
            issues.append(
                HealthIssue(
                    category: .security,
                    status: .critical,
                    title: "FileVault is disabled",
                    explanation: "fdesetup reported that FileVault is off."
                )
            )
        }

        if diagnostics.systemIntegrityProtectionEnabled == false {
            issues.append(
                HealthIssue(
                    category: .security,
                    status: .critical,
                    title: "System Integrity Protection is disabled",
                    explanation: "csrutil reported SIP disabled."
                )
            )
        }

        if diagnostics.firewallEnabled == false {
            issues.append(
                HealthIssue(
                    category: .security,
                    status: .warning,
                    title: "Firewall appears to be disabled",
                    explanation: "The Application Firewall global state is off."
                )
            )
        }

        if let pendingSecurityUpdatesCount = diagnostics.pendingSecurityUpdatesCount, pendingSecurityUpdatesCount >= Thresholds.warningSecurityUpdateCount {
            let labelPreview = diagnostics.availableSecurityUpdateLabels.prefix(2).joined(separator: ", ")
            let explanation = labelPreview.isEmpty
                ? "\(pendingSecurityUpdatesCount) software update(s) are available."
                : "\(pendingSecurityUpdatesCount) software update(s) are available, including \(labelPreview)."
            issues.append(
                HealthIssue(
                    category: .security,
                    status: .warning,
                    title: "Software updates are available",
                    explanation: explanation
                )
            )
        }

        return issues
    }

    private func securityRecommendations(
        for diagnostics: SecurityDiagnostics
    ) -> [MaintenanceRecommendation] {
        var recommendations: [MaintenanceRecommendation] = []

        if diagnostics.fileVaultEnabled == false {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review FileVault in Privacy & Security",
                    explanation: "Use System Settings > Privacy & Security > FileVault to confirm whether disk encryption should be enabled on this Mac.",
                    riskLevel: .advanced,
                    estimatedImpact: "Enabling FileVault improves data protection at rest.",
                    reversibility: "This is a user-managed system setting and may require time to complete.",
                    relatedCategory: .security
                )
            )
        }

        if diagnostics.gatekeeperEnabled == false {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review Gatekeeper in Privacy & Security",
                    explanation: "Use System Settings > Privacy & Security to confirm the app-allowance policy is set intentionally.",
                    riskLevel: .review,
                    estimatedImpact: "Re-enabling Gatekeeper helps block untrusted app launches.",
                    reversibility: "System Settings change is reversible by the user.",
                    relatedCategory: .security
                )
            )
        }

        if diagnostics.firewallEnabled == false {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review Firewall in System Settings",
                    explanation: "Use System Settings > Network > Firewall to confirm whether inbound protection should be enabled.",
                    riskLevel: .review,
                    estimatedImpact: "Enabling the firewall can reduce unnecessary inbound exposure.",
                    reversibility: "System Settings change is reversible by the user.",
                    relatedCategory: .security
                )
            )
        }

        if diagnostics.systemIntegrityProtectionEnabled == false {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review the SIP exception",
                    explanation: "If SIP was disabled intentionally, confirm the exception is still required. SIP changes must be handled outside this app and should be treated as an advanced review.",
                    riskLevel: .advanced,
                    estimatedImpact: "Re-enabling SIP restores a major system protection layer.",
                    reversibility: "Requires a manual recovery-environment workflow and should be planned carefully.",
                    relatedCategory: .security
                )
            )
        }

        if let pendingSecurityUpdatesCount = diagnostics.pendingSecurityUpdatesCount, pendingSecurityUpdatesCount > 0 {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review Software Update in System Settings",
                    explanation: "Use System Settings > General > Software Update to review available updates before installing anything.",
                    riskLevel: .review,
                    estimatedImpact: "\(pendingSecurityUpdatesCount) update(s) are visible to softwareupdate.",
                    reversibility: "Review is read-only; installation remains a separate manual choice.",
                    relatedCategory: .security
                )
            )
        }

        if !diagnostics.commandFailures.isEmpty || diagnostics.status == .unknown {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review incomplete security visibility",
                    explanation: "Some requested security checks were unavailable or partially visible. Confirm the missing areas manually before treating the security picture as complete.",
                    riskLevel: .safe,
                    estimatedImpact: "Improves confidence in Gatekeeper, FileVault, firewall, XProtect, and update visibility.",
                    reversibility: "Read-only review only.",
                    relatedCategory: .security
                )
            )
        }

        return recommendations
    }

    private func securityStatus(from issues: [HealthIssue]) -> HealthStatus {
        if issues.contains(where: { $0.status == .critical }) {
            return .critical
        }

        if issues.contains(where: { $0.status == .warning }) {
            return .warning
        }

        if issues.contains(where: { $0.status == .unknown }) {
            return .unknown
        }

        return .healthy
    }

    private func unavailableMetricNames(diagnostics: SecurityDiagnostics) -> [String] {
        var names: [String] = []

        if diagnostics.gatekeeperEnabled == nil {
            names.append("Gatekeeper status")
        }

        if diagnostics.fileVaultEnabled == nil {
            names.append("FileVault status")
        }

        if diagnostics.systemIntegrityProtectionEnabled == nil {
            names.append("SIP status")
        }

        if diagnostics.firewallEnabled == nil {
            names.append("Firewall status")
        }

        if diagnostics.xProtectPayload == nil {
            names.append("XProtect payload version")
        }

        if diagnostics.xProtectConfigData == nil {
            names.append("XProtect config data version")
        }

        if diagnostics.pendingSecurityUpdatesCount == nil {
            names.append("Software Update visibility")
        }

        return names
    }

    private func currentMacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let numericVersion: String
        if version.patchVersion > 0 {
            numericVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        } else {
            numericVersion = "\(version.majorVersion).\(version.minorVersion)"
        }

        return "macOS \(numericVersion)"
    }

    private func parseGatekeeperStatus(from output: String) -> Bool? {
        let lowered = output.lowercased()
        if lowered.contains("assessments enabled") {
            return true
        }
        if lowered.contains("assessments disabled") {
            return false
        }
        return nil
    }

    private func parseFileVaultStatus(from output: String) -> Bool? {
        if output.contains("FileVault is On.") {
            return true
        }
        if output.contains("FileVault is Off.") {
            return false
        }
        return nil
    }

    private func parseSIPStatus(from output: String) -> Bool? {
        let lowered = output.lowercased()
        if lowered.contains("system integrity protection status: enabled") {
            return true
        }
        if lowered.contains("system integrity protection status: disabled") {
            return false
        }
        return nil
    }

    private func parseFirewallStatus(from output: String) -> Bool? {
        let lowered = output.lowercased()
        if lowered.contains("firewall is enabled") {
            return true
        }
        if lowered.contains("firewall is disabled") {
            return false
        }
        return nil
    }

    private func latestPackageIdentifier(
        matchingPrefix prefix: String,
        packageIdentifiers: [String]
    ) -> String? {
        packageIdentifiers
            .filter { $0.hasPrefix(prefix) }
            .max { lhs, rhs in
                lhs.compare(rhs, options: [.numeric]) == .orderedAscending
            }
    }

    private func parsePackageReceipt(_ output: String) -> SecurityDiagnostics.PackageReceipt? {
        var packageIdentifier: String?
        var version: String?
        var installDate: Date?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = value(forPrefix: "package-id:", in: line) {
                packageIdentifier = value
            } else if let value = value(forPrefix: "version:", in: line) {
                version = value
            } else if let value = value(forPrefix: "install-time:", in: line), let timeInterval = TimeInterval(value) {
                installDate = Date(timeIntervalSince1970: timeInterval)
            }
        }

        guard let packageIdentifier, let version else {
            return nil
        }

        return SecurityDiagnostics.PackageReceipt(
            packageIdentifier: packageIdentifier,
            version: version,
            installDate: installDate
        )
    }

    private func parseSoftwareUpdateInfo(_ output: String) -> (count: Int, labels: [String])? {
        if output.contains("No new software available.") {
            return (0, [])
        }

        let labels = output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> String? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let range = line.range(of: "Label: ") else {
                    return nil
                }
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        return labels.isEmpty ? nil : (labels.count, labels)
    }

    private func combinedOutput(from result: SafeCommandRunner.ExecutionResult) -> String {
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (stdout.isEmpty, stderr.isEmpty) {
        case (false, false):
            return stdout + "\n" + stderr
        case (false, true):
            return stdout
        case (true, false):
            return stderr
        case (true, true):
            return ""
        }
    }

    private func commandFailure(
        from result: SafeCommandRunner.ExecutionResult
    ) -> SecurityDiagnostics.CommandFailure {
        let message: String
        switch result.failureReason {
        case .launchFailed(let detail):
            message = "Command could not be launched: \(detail)"
        case .timedOut(let timeout):
            message = "Command timed out after \(Int(timeout.rounded())) second(s)."
        case .nonZeroExit:
            message = "Command exited with status \(result.exitStatus)."
        case nil:
            message = "Command output could not be interpreted."
        }

        return SecurityDiagnostics.CommandFailure(
            command: result.command.displayName,
            arguments: result.arguments,
            message: message,
            standardError: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func value(forPrefix prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else {
            return nil
        }

        return line
            .replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
