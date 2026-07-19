import Foundation

struct GeneratedReportFiles: Equatable, Sendable {
    let generatedAt: Date
    let markdownURL: URL
    let jsonURL: URL
}

struct ReportStore {
    struct Configuration: Equatable, Sendable {
        var homeDirectoryURL: URL

        init(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
            self.homeDirectoryURL = homeDirectoryURL
        }

        var reportsDirectoryURL: URL {
            homeDirectoryURL
                .appendingPathComponent("Reports", isDirectory: true)
                .appendingPathComponent("MacHealthOS", isDirectory: true)
        }
    }

    private struct PersistedHealthReport: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let report: HealthReport
        let scoreSummary: HealthScoreEngine.Evaluation
    }

    private let fileManager = FileManager.default
    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func writeReport(report: HealthReport) throws -> GeneratedReportFiles {
        let reportsDirectory = try reportsDirectoryURL()
        let stamp = TimestampFormatter.reportFileNameString(from: report.generatedAt)
        let baseName = "mac_health_os_\(stamp)"
        let markdownURL = reportsDirectory.appendingPathComponent(baseName).appendingPathExtension("md")
        let jsonURL = reportsDirectory.appendingPathComponent(baseName).appendingPathExtension("json")

        try renderMarkdown(for: report).write(to: markdownURL, atomically: true, encoding: .utf8)

        let payload = PersistedHealthReport(
            schemaVersion: 1,
            report: report,
            scoreSummary: report.scoreSummary
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.jsonDateString(from: date))
        }
        let data = try encoder.encode(payload)
        try data.write(to: jsonURL, options: .atomic)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let stringValue = try container.decode(String.self)

            if let date = Self.date(fromJSONString: stringValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(stringValue)"
            )
        }
        _ = try decoder.decode(PersistedHealthReport.self, from: Data(contentsOf: jsonURL))

        return GeneratedReportFiles(
            generatedAt: report.generatedAt,
            markdownURL: markdownURL,
            jsonURL: jsonURL
        )
    }

    func markdownString(for report: HealthReport) -> String {
        renderMarkdown(for: report)
    }

    func reportsDirectoryURL() throws -> URL {
        try resolvedReportsDirectoryURL()
    }

    func latestReportFiles() throws -> GeneratedReportFiles? {
        let reportsDirectory = try reportsDirectoryURL()
        guard fileManager.fileExists(atPath: reportsDirectory.path) else {
            return nil
        }

        let reportURLs = try fileManager.contentsOfDirectory(
            at: reportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let markdownURLs = reportURLs
            .filter { $0.lastPathComponent.hasPrefix("mac_health_os_") && $0.pathExtension == "md" }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedDescending
            }

        for markdownURL in markdownURLs {
            let jsonURL = markdownURL.deletingPathExtension().appendingPathExtension("json")
            guard fileManager.fileExists(atPath: jsonURL.path) else {
                continue
            }

            let generatedAt = (try? markdownURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return GeneratedReportFiles(
                generatedAt: generatedAt,
                markdownURL: markdownURL,
                jsonURL: jsonURL
            )
        }

        return nil
    }

    private static func jsonDateString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(fromJSONString string: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: string) {
            return date
        }

        let formatterWithoutFractionalSeconds = ISO8601DateFormatter()
        formatterWithoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractionalSeconds.date(from: string)
    }

    private func renderMarkdown(for report: HealthReport) -> String {
        let scoreSummary = report.scoreSummary
        let sections = [
            """
            # Mac Health OS Report

            - Timestamp: \(TimestampFormatter.iso8601String(from: report.generatedAt))
            - Machine Name: \(report.machine.machineName)
            - macOS Version: \(report.machine.macOSVersion)
            - Hardware Architecture: \(report.machine.hardwareArchitecture)
            - Health Score: \(scoreSummary.scoreDisplayText)
            - Overall Status: \(scoreSummary.overallStatus.displayName)
            """,
            markdownIssuesSection(report.topIssues),
            markdownStorageSection(report.storage),
            markdownPerformanceSection(report.performance),
            markdownSecuritySection(report.security),
            markdownAutomationSection(report.automation),
            markdownRecommendationsSection(report.recommendations),
            markdownMaintenanceActionsSection(report.maintenanceActions),
            markdownAIExplanationSection(report.aiExplanation),
            """
            ## Latest App Status

            \(report.lastStatusMessage)
            """,
        ]

        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func markdownIssuesSection(_ issues: [HealthIssue]) -> String {
        guard !issues.isEmpty else {
            return """
            ## Top Issues

            - No issues were identified in this report.
            """
        }

        let items = issues.prefix(3).map { issue in
            "- [\(issue.status.displayName)] \(issue.title): \(issue.explanation)"
        }

        return """
        ## Top Issues

        \(items.joined(separator: "\n"))
        """
    }

    private func markdownStorageSection(_ diagnostics: StorageDiagnostics) -> String {
        var lines = [
            "## Storage Findings",
            "",
            "- Status: \(diagnostics.status.displayName)",
            "- Total Capacity: \(diagnostics.totalCapacityBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Used Space: \(diagnostics.usedCapacityBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Free Space: \(diagnostics.freeCapacityBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Free Percentage: \(diagnostics.freeCapacityPercent.map(StorageFormatters.percentageString(from:)) ?? "Unknown")",
            "- Downloads Size: \(diagnostics.downloadsSizeBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Trash Size: \(diagnostics.trashSizeBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Caches Size: \(diagnostics.cachesSizeBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
        ]

        lines.append(contentsOf: diagnostics.issues.map { "- Issue: [\($0.status.displayName)] \($0.title) - \($0.explanation)" })
        lines.append(contentsOf: diagnostics.largeFiles.prefix(5).map {
            "- Large File: \($0.path) (\(StorageFormatters.byteCountString(from: $0.sizeBytes)))"
        })
        lines.append(contentsOf: diagnostics.oldDownloads.prefix(5).map {
            "- Old Downloads File: \($0.path) (\(StorageFormatters.byteCountString(from: $0.sizeBytes)))"
        })
        lines.append(contentsOf: diagnostics.scanErrors.prefix(5).map {
            "- Scan Note: \($0.operation) at \($0.path) - \($0.message)"
        })

        return lines.joined(separator: "\n")
    }

    private func markdownPerformanceSection(_ diagnostics: PerformanceDiagnostics) -> String {
        var lines = [
            "## Performance Findings",
            "",
            "- Status: \(diagnostics.status.displayName)",
            "- CPU Load: \(diagnostics.cpuLoadPercent.map(PerformanceFormatters.cpuLoadString(from:)) ?? "Unknown")",
            "- Memory Pressure: \(diagnostics.memoryPressureSummary ?? "Unknown")",
            "- Physical Memory: \(diagnostics.physicalMemoryBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Used Memory: \(diagnostics.usedMemoryBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Available Memory: \(diagnostics.availableMemoryBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown")",
            "- Uptime: \(diagnostics.uptimeSeconds.map(PerformanceFormatters.durationString(from:)) ?? "Unknown")",
            "- Background Services: \(diagnostics.backgroundServiceCount.map(String.init) ?? "Unknown")",
            "- Active Services: \(diagnostics.activeBackgroundServiceCount.map(String.init) ?? "Unknown")",
        ]

        lines.append(contentsOf: diagnostics.issues.map { "- Issue: [\($0.status.displayName)] \($0.title) - \($0.explanation)" })
        lines.append(contentsOf: diagnostics.topCPUProcesses.prefix(5).map {
            "- Top CPU Process: \($0.command) (PID \($0.pid), CPU \(PerformanceFormatters.cpuLoadString(from: $0.cpuPercent ?? 0)))"
        })
        lines.append(contentsOf: diagnostics.topMemoryProcesses.prefix(5).map {
            "- Top Memory Process: \($0.command) (PID \($0.pid), RSS \($0.residentMemoryBytes.map(StorageFormatters.byteCountString(from:)) ?? "Unknown"))"
        })
        lines.append(contentsOf: diagnostics.accessibleLoginItemLabels.prefix(10).map { "- Login Item Label: \($0)" })
        lines.append(contentsOf: diagnostics.enabledUserServiceLabels.prefix(10).map { "- Enabled User Service: \($0)" })
        lines.append(contentsOf: diagnostics.commandFailures.prefix(5).flatMap(markdownCommandFailureLines))

        return lines.joined(separator: "\n")
    }

    private func markdownSecuritySection(_ diagnostics: SecurityDiagnostics) -> String {
        var lines = [
            "## Security Findings",
            "",
            "- Status: \(diagnostics.status.displayName)",
            "- Gatekeeper: \(boolText(diagnostics.gatekeeperEnabled))",
            "- FileVault: \(boolText(diagnostics.fileVaultEnabled))",
            "- SIP: \(boolText(diagnostics.systemIntegrityProtectionEnabled))",
            "- Firewall: \(boolText(diagnostics.firewallEnabled))",
            "- macOS Version: \(diagnostics.macOSVersion ?? "Unknown")",
            "- Software Updates: \(securityUpdateText(diagnostics.pendingSecurityUpdatesCount))",
            "- XProtect Payload: \(diagnostics.xProtectPayload.map { "\($0.packageIdentifier) (\($0.version))" } ?? "Unknown")",
            "- XProtect Config: \(diagnostics.xProtectConfigData.map { "\($0.packageIdentifier) (\($0.version))" } ?? "Unknown")",
        ]

        lines.append(contentsOf: diagnostics.issues.map { "- Issue: [\($0.status.displayName)] \($0.title) - \($0.explanation)" })
        lines.append(contentsOf: diagnostics.availableSecurityUpdateLabels.prefix(10).map { "- Available Update: \($0)" })
        lines.append(contentsOf: diagnostics.commandFailures.prefix(5).flatMap(markdownCommandFailureLines))

        return lines.joined(separator: "\n")
    }

    private func markdownAutomationSection(_ diagnostics: AutomationDiagnostics) -> String {
        var lines = [
            "## Automation Findings",
            "",
            "- Status: \(diagnostics.status.displayName)",
            "- User LaunchAgents: \(diagnostics.userLaunchAgents.count)",
            "- Shared LaunchAgents: \(diagnostics.sharedLaunchAgents.count)",
            "- System LaunchAgents: \(diagnostics.systemLaunchAgentCount.map(String.init) ?? "Unknown")",
            "- System KeepAlive: \(diagnostics.systemKeepAliveCount.map(String.init) ?? "Unknown")",
            "- Broken Plists: \(diagnostics.brokenPlistLabels.count)",
            "- Missing Executables: \(diagnostics.missingExecutableLabels.count)",
            "- Stale Log Paths: \(diagnostics.staleLogPathLabels.count)",
            "- KeepAlive Agents: \(diagnostics.keepAliveAgentLabels.count)",
            "- Homebrew Services: \(diagnostics.homebrewServices.count)",
        ]

        lines.append(contentsOf: diagnostics.issues.map { "- Issue: [\($0.status.displayName)] \($0.title) - \($0.explanation)" })
        lines.append(contentsOf: diagnostics.keepAliveAgentLabels.prefix(10).map { "- KeepAlive Label: \($0)" })
        lines.append(contentsOf: diagnostics.homebrewServices.prefix(10).map { "- Homebrew Service: \($0.name) (\($0.status))" })
        lines.append(contentsOf: diagnostics.commonFolders.map {
            "- Automation Folder: \($0.title) - \(folderStateText($0)) at \($0.path)"
        })
        lines.append(contentsOf: diagnostics.scanNotes.prefix(5).map {
            "- Scan Note: \($0.operation) at \($0.path) - \($0.message)"
        })
        lines.append(contentsOf: diagnostics.commandFailures.prefix(5).flatMap(markdownCommandFailureLines))

        return lines.joined(separator: "\n")
    }

    private func markdownRecommendationsSection(_ recommendations: [MaintenanceRecommendation]) -> String {
        guard !recommendations.isEmpty else {
            return """
            ## Maintenance Recommendations

            - No recommendations were generated.
            """
        }

        let lines = recommendations.map { recommendation in
            """
            - [\(recommendation.riskLevel.rawValue)] \(recommendation.title)
              Category: \(recommendation.relatedCategory.displayName)
              Why: \(recommendation.explanation)
              Estimated Impact: \(recommendation.estimatedImpact)
              Reversibility: \(recommendation.reversibility)
            """
        }

        return """
        ## Maintenance Recommendations

        \(lines.joined(separator: "\n"))
        """
    }

    private func markdownMaintenanceActionsSection(_ actions: [MaintenanceActionRecord]) -> String {
        guard !actions.isEmpty else {
            return """
            ## Maintenance Action Log

            - No maintenance actions have been recorded yet.
            """
        }

        let lines = actions.prefix(20).map { action in
            """
            - \(TimestampFormatter.iso8601String(from: action.timestamp)) [\(action.result.displayName)] \(action.title)
              Risk: \(action.riskLevel.rawValue)
              Why: \(action.explanation)
              Impact: \(action.estimatedImpact)
              Reversibility: \(action.reversibility)
              Details: \(action.details)
            """
        }

        return """
        ## Maintenance Action Log

        \(lines.joined(separator: "\n"))
        """
    }

    private func markdownAIExplanationSection(_ explanation: AIExplanation?) -> String {
        guard let explanation else {
            return ""
        }

        let sectionBodies = explanation.sections.map { section in
            let body: String
            if section.items.isEmpty {
                body = "- None."
            } else {
                body = section.items.map { "- \($0)" }.joined(separator: "\n")
            }

            return """
            ### \(section.title)

            \(body)
            """
        }

        return """
        ## AI Explanation (Advisory)

        - Provider: \(explanation.provider.displayName)
        - Generated: \(TimestampFormatter.iso8601String(from: explanation.generatedAt))
        - Disclaimer: \(explanation.disclaimer)

        \(sectionBodies.joined(separator: "\n\n"))
        """
    }

    private func markdownCommandFailureLines(
        commandFailure: some CommandFailureDescribing
    ) -> [String] {
        var lines = [
            "- Command Failure: \(commandFailure.command) - \(commandFailure.message)"
        ]

        let stderr = commandFailure.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            lines.append("  Safe Output: \(stderr)")
        }

        return lines
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else {
            return "Unknown"
        }

        return value ? "Enabled" : "Disabled"
    }

    private func securityUpdateText(_ count: Int?) -> String {
        guard let count else {
            return "Unknown"
        }

        return count == 0 ? "No updates detected" : "\(count) visible update(s)"
    }

    private func folderStateText(_ folder: AutomationDiagnostics.FolderSnapshot) -> String {
        if !folder.exists {
            return "Not present"
        }

        if folder.readable == false {
            return "Unreadable"
        }

        return "\(folder.itemCount ?? 0) item(s)"
    }

    private func resolvedReportsDirectoryURL() throws -> URL {
        let reportsDirectory = configuration.reportsDirectoryURL
        try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        return reportsDirectory
    }
}

private protocol CommandFailureDescribing {
    var command: String { get }
    var message: String { get }
    var standardError: String { get }
}

extension PerformanceDiagnostics.CommandFailure: CommandFailureDescribing {}
extension SecurityDiagnostics.CommandFailure: CommandFailureDescribing {}
extension AutomationDiagnostics.CommandFailure: CommandFailureDescribing {}
