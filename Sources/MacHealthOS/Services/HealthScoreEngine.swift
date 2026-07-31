import Foundation

struct HealthScoreEngine {
    static let `default` = HealthScoreEngine()

    struct ScoreComponent: Codable, Equatable, Sendable {
        let category: DiagnosticCategory
        let weightPercentage: Double
        let status: HealthStatus
        let rawScore: Int
        let weightedScore: Double
        let explanation: String
    }

    struct Evaluation: Codable, Equatable, Sendable {
        let overallScore: Int
        let overallStatus: HealthStatus
        let components: [ScoreComponent]
        let topIssues: [HealthIssue]
        let recommendations: [MaintenanceRecommendation]

        var scoreDisplayText: String {
            overallStatus == .unknown ? "Unknown" : String(overallScore)
        }
    }

    func evaluate(_ report: HealthReport) -> Evaluation {
        let storageComponent = scoreStorage(report.storage)
        let performanceComponent = scorePerformance(report.performance)
        let securityComponent = scoreSecurity(report.security)
        let automationComponent = scoreAutomation(report.automation)
        let maintenanceComponent = scoreMaintenance(
            lastApprovedMaintenanceAt: report.lastApprovedMaintenanceAt ?? report.lastMaintenanceDate,
            lastReadOnlyHealthScanAt: report.lastReadOnlyHealthScanAt,
            generatedAt: report.generatedAt
        )

        let components = [
            storageComponent,
            performanceComponent,
            securityComponent,
            automationComponent,
            maintenanceComponent,
        ]

        let overallScore = Int(components.reduce(0.0) { partialResult, component in
            partialResult + component.weightedScore
        }.rounded())

        return Evaluation(
            overallScore: overallScore,
            overallStatus: overallStatus(from: components),
            components: components,
            topIssues: Array(topIssues(from: report).prefix(3)),
            recommendations: sortedRecommendations(report.recommendations)
        )
    }

    private func scoreStorage(_ diagnostics: StorageDiagnostics) -> ScoreComponent {
        scoreComponent(
            category: .storage,
            status: diagnostics.status,
            issues: diagnostics.issues,
            explanationParts: [
                "status \(diagnostics.status.displayName.lowercased())",
                metricsDescription([
                    diagnostics.totalCapacityBytes.map { "total \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.usedCapacityBytes.map { "used \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.freeCapacityBytes.map { "free \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.freeCapacityPercent.map { "free \(StorageFormatters.percentageString(from: $0))" },
                    diagnostics.downloadsSizeBytes.map { "Downloads \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.trashSizeBytes.map { "Trash \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.cachesSizeBytes.map { "Caches \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.largeFiles.isEmpty ? nil : "\(diagnostics.largeFiles.count) large files above \(StorageFormatters.byteCountString(from: diagnostics.largeFileThresholdBytes))",
                    diagnostics.oldDownloads.isEmpty ? nil : "\(diagnostics.oldDownloads.count) old Downloads files",
                    diagnostics.scanErrors.isEmpty ? nil : "\(diagnostics.scanErrors.count) scan access issues",
                ]),
            ]
        )
    }

    private func scorePerformance(_ diagnostics: PerformanceDiagnostics) -> ScoreComponent {
        scoreComponent(
            category: .performance,
            status: diagnostics.status,
            issues: diagnostics.issues,
            explanationParts: [
                "status \(diagnostics.status.displayName.lowercased())",
                metricsDescription([
                    diagnostics.cpuLoadPercent.map { "CPU load \(PerformanceFormatters.cpuLoadString(from: $0))" },
                    diagnostics.memoryPressureSummary.map { "memory pressure: \($0)" },
                    diagnostics.physicalMemoryBytes.map { "physical \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.usedMemoryBytes.map { "used \(StorageFormatters.byteCountString(from: $0))" },
                    diagnostics.uptimeSeconds.map { "uptime \(PerformanceFormatters.durationString(from: $0))" },
                    diagnostics.topCPUProcesses.isEmpty ? nil : "top CPU: \(diagnostics.topCPUProcesses.prefix(3).map(\.command).joined(separator: ", "))",
                    diagnostics.topMemoryProcesses.isEmpty ? nil : "top memory: \(diagnostics.topMemoryProcesses.prefix(3).map(\.command).joined(separator: ", "))",
                    diagnostics.enabledUserServiceLabels.isEmpty ? nil : "\(diagnostics.enabledUserServiceLabels.count) enabled user services",
                    diagnostics.commandFailures.isEmpty ? nil : "\(diagnostics.commandFailures.count) command failures",
                ]),
            ]
        )
    }

    private func scoreSecurity(_ diagnostics: SecurityDiagnostics) -> ScoreComponent {
        scoreComponent(
            category: .security,
            status: diagnostics.status,
            issues: diagnostics.issues,
            explanationParts: [
                "status \(diagnostics.status.displayName.lowercased())",
                metricsDescription([
                    diagnostics.gatekeeperEnabled.map { "Gatekeeper \($0 ? "enabled" : "disabled")" },
                    diagnostics.fileVaultEnabled.map { "FileVault \($0 ? "enabled" : "disabled")" },
                    diagnostics.systemIntegrityProtectionEnabled.map { "SIP \($0 ? "enabled" : "disabled")" },
                    diagnostics.firewallEnabled.map { "Firewall \($0 ? "enabled" : "disabled")" },
                    diagnostics.macOSVersion,
                    diagnostics.xProtectPayload.map { "XProtect payload \($0.version)" },
                    diagnostics.xProtectConfigData.map { "XProtect config \($0.version)" },
                    diagnostics.pendingSecurityUpdatesCount.map { "\($0) visible software updates" },
                    diagnostics.commandFailures.isEmpty ? nil : "\(diagnostics.commandFailures.count) command failures",
                ]),
            ]
        )
    }

    private func scoreAutomation(_ diagnostics: AutomationDiagnostics) -> ScoreComponent {
        scoreComponent(
            category: .automation,
            status: diagnostics.status,
            issues: diagnostics.issues,
            explanationParts: [
                "status \(diagnostics.status.displayName.lowercased())",
                metricsDescription([
                    !diagnostics.userLaunchAgents.isEmpty ? "\(diagnostics.userLaunchAgents.count) user LaunchAgents" : nil,
                    !diagnostics.sharedLaunchAgents.isEmpty ? "\(diagnostics.sharedLaunchAgents.count) shared LaunchAgents" : nil,
                    diagnostics.systemLaunchAgentCount.map { "\($0) system LaunchAgents" },
                    diagnostics.keepAliveAgentLabels.isEmpty ? nil : "\(diagnostics.keepAliveAgentLabels.count) KeepAlive agents",
                    diagnostics.brokenPlistLabels.isEmpty ? nil : "\(diagnostics.brokenPlistLabels.count) invalid plists",
                    diagnostics.missingExecutableLabels.isEmpty ? nil : "\(diagnostics.missingExecutableLabels.count) missing executables",
                    diagnostics.staleLogPathLabels.isEmpty ? nil : "\(diagnostics.staleLogPathLabels.count) stale log paths",
                    diagnostics.homebrewServices.isEmpty ? nil : "\(diagnostics.homebrewServices.count) Homebrew services",
                    diagnostics.commandFailures.isEmpty ? nil : "\(diagnostics.commandFailures.count) command failures",
                ]),
            ]
        )
    }

    private func scoreMaintenance(
        lastApprovedMaintenanceAt: Date?,
        lastReadOnlyHealthScanAt: Date?,
        generatedAt: Date
    ) -> ScoreComponent {
        let assessment = maintenanceAssessment(
            lastApprovedMaintenanceAt: lastApprovedMaintenanceAt,
            lastReadOnlyHealthScanAt: lastReadOnlyHealthScanAt,
            generatedAt: generatedAt
        )

        return ScoreComponent(
            category: .maintenance,
            weightPercentage: DiagnosticCategory.maintenance.weightPercentage,
            status: assessment.status,
            rawScore: assessment.rawScore,
            weightedScore: Double(assessment.rawScore) * DiagnosticCategory.maintenance.weightPercentage / 100.0,
            explanation: assessment.explanation
        )
    }

    private func scoreComponent(
        category: DiagnosticCategory,
        status: HealthStatus,
        issues: [HealthIssue],
        explanationParts: [String]
    ) -> ScoreComponent {
        let penalty = issues.reduce(0) { partialResult, issue in
            partialResult + issuePenalty(for: issue.status)
        }
        let rawScore = max(0, status.baseScore - penalty)
        let weightedScore = Double(rawScore) * category.weightPercentage / 100.0

        let issueSummary: String
        switch issues.count {
        case 0:
            issueSummary = "no explicit issues recorded"
        case 1:
            issueSummary = "1 issue recorded"
        default:
            issueSummary = "\(issues.count) issues recorded"
        }

        let description = ([category.displayName, explanationParts.joined(separator: "; "), issueSummary]
            .filter { !$0.isEmpty })
            .joined(separator: " | ")

        return ScoreComponent(
            category: category,
            weightPercentage: category.weightPercentage,
            status: status,
            rawScore: rawScore,
            weightedScore: weightedScore,
            explanation: description
        )
    }

    private func overallStatus(from components: [ScoreComponent]) -> HealthStatus {
        let statuses = components.map(\.status)

        if statuses.contains(.critical) {
            return .critical
        }

        if statuses.contains(.warning) {
            return .warning
        }

        if statuses.allSatisfy({ $0 == .healthy }) {
            return .healthy
        }

        return .unknown
    }

    private func topIssues(from report: HealthReport) -> [HealthIssue] {
        let issues = collectedIssues(from: report)

        return issues.sorted { lhs, rhs in
            if lhs.status.severityRank != rhs.status.severityRank {
                return lhs.status.severityRank > rhs.status.severityRank
            }

            if lhs.category.weightPercentage != rhs.category.weightPercentage {
                return lhs.category.weightPercentage > rhs.category.weightPercentage
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func collectedIssues(from report: HealthReport) -> [HealthIssue] {
        var issues: [HealthIssue] = []
        issues.append(contentsOf: issuesForCategory(.storage, status: report.storage.status, issues: report.storage.issues))
        issues.append(contentsOf: issuesForCategory(.performance, status: report.performance.status, issues: report.performance.issues))
        issues.append(contentsOf: issuesForCategory(.security, status: report.security.status, issues: report.security.issues))
        issues.append(contentsOf: issuesForCategory(.automation, status: report.automation.status, issues: report.automation.issues))

        if let maintenanceIssue = maintenanceAssessment(
            lastApprovedMaintenanceAt: report.lastApprovedMaintenanceAt ?? report.lastMaintenanceDate,
            lastReadOnlyHealthScanAt: report.lastReadOnlyHealthScanAt,
            generatedAt: report.generatedAt
        ).issue {
            issues.append(maintenanceIssue)
        }

        return issues
    }

    private func issuesForCategory(
        _ category: DiagnosticCategory,
        status: HealthStatus,
        issues: [HealthIssue]
    ) -> [HealthIssue] {
        if !issues.isEmpty {
            return issues
        }

        guard status != .healthy else {
            return []
        }

        return [
            HealthIssue(
                category: category,
                status: status,
                title: "\(category.displayName) status is \(status.displayName.lowercased())",
                explanation: "\(category.displayName) diagnostics did not provide enough healthy evidence to clear this category."
            )
        ]
    }

    private func maintenanceAssessment(
        lastApprovedMaintenanceAt: Date?,
        lastReadOnlyHealthScanAt: Date?,
        generatedAt: Date
    ) -> (status: HealthStatus, rawScore: Int, explanation: String, issue: HealthIssue?) {
        // Approved remediation history drives age-based maintenance freshness when present.
        if let lastApprovedMaintenanceAt {
            let daysSinceMaintenance = max(0, Int(generatedAt.timeIntervalSince(lastApprovedMaintenanceAt) / 86_400))

            if daysSinceMaintenance <= 14 {
                return (
                    status: .healthy,
                    rawScore: HealthStatus.healthy.baseScore,
                    explanation: "Maintenance | last approved maintenance was \(daysSinceMaintenance) day(s) ago",
                    issue: nil
                )
            }

            if daysSinceMaintenance <= 45 {
                return (
                    status: .warning,
                    rawScore: HealthStatus.warning.baseScore,
                    explanation: "Maintenance | last approved maintenance was \(daysSinceMaintenance) day(s) ago",
                    issue: HealthIssue(
                        category: .maintenance,
                        status: .warning,
                        title: "Maintenance is getting stale",
                        explanation: "The last approved maintenance run was \(daysSinceMaintenance) day(s) ago."
                    )
                )
            }

            return (
                status: .critical,
                rawScore: HealthStatus.critical.baseScore,
                explanation: "Maintenance | last approved maintenance was \(daysSinceMaintenance) day(s) ago",
                issue: HealthIssue(
                    category: .maintenance,
                    status: .critical,
                    title: "Maintenance freshness is critical",
                    explanation: "The last approved maintenance run was \(daysSinceMaintenance) day(s) ago."
                )
            )
        }

        // A recent successful read-only scan proves monitoring freshness.
        // Lack of remediation history is not itself a health fault.
        if let lastReadOnlyHealthScanAt {
            let daysSinceScan = max(0, Int(generatedAt.timeIntervalSince(lastReadOnlyHealthScanAt) / 86_400))
            return (
                status: .healthy,
                rawScore: HealthStatus.healthy.baseScore,
                explanation: "Maintenance | monitoring fresh (last read-only scan \(daysSinceScan) day(s) ago); no approved remediation recorded yet",
                issue: nil
            )
        }

        return (
            status: .unknown,
            rawScore: HealthStatus.unknown.baseScore,
            explanation: "Maintenance | no scan or approved maintenance timestamp recorded",
            issue: HealthIssue(
                category: .maintenance,
                status: .unknown,
                title: "Maintenance freshness is unknown",
                explanation: "No timestamp is available for the last read-only health scan or approved maintenance run."
            )
        )
    }

    private func metricsDescription(_ parts: [String?]) -> String {
        let presentParts = parts.compactMap { $0 }
        return presentParts.isEmpty ? "metrics unavailable" : presentParts.joined(separator: "; ")
    }

    private func issuePenalty(for status: HealthStatus) -> Int {
        switch status {
        case .healthy:
            0
        case .warning:
            10
        case .critical:
            20
        case .unknown:
            5
        }
    }

    private func sortedRecommendations(_ recommendations: [MaintenanceRecommendation]) -> [MaintenanceRecommendation] {
        recommendations.sorted { lhs, rhs in
            if lhs.riskLevel.severityRank != rhs.riskLevel.severityRank {
                return lhs.riskLevel.severityRank > rhs.riskLevel.severityRank
            }

            if lhs.relatedCategory.weightPercentage != rhs.relatedCategory.weightPercentage {
                return lhs.relatedCategory.weightPercentage > rhs.relatedCategory.weightPercentage
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
