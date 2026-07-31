import Foundation
import Testing
@testable import MacHealthOS

@Test func healthyScoreReachesOneHundred() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let report = HealthReport(
        generatedAt: generatedAt,
        storage: StorageDiagnostics(
            status: .healthy,
            totalCapacityBytes: 500 * 1_073_741_824,
            usedCapacityBytes: 250 * 1_073_741_824,
            freeCapacityBytes: 250 * 1_073_741_824,
            freeCapacityPercent: 50
        ),
        performance: PerformanceDiagnostics(
            status: .healthy,
            cpuLoadPercent: 18.0,
            memoryPressureSummary: "normal",
            physicalMemoryBytes: 16 * 1_073_741_824,
            usedMemoryBytes: 8 * 1_073_741_824,
            uptimeSeconds: 7_200
        ),
        security: SecurityDiagnostics(
            status: .healthy,
            gatekeeperEnabled: true,
            fileVaultEnabled: true,
            systemIntegrityProtectionEnabled: true,
            firewallEnabled: true,
            pendingSecurityUpdatesCount: 0
        ),
        automation: AutomationDiagnostics(status: .healthy),
        lastMaintenanceDate: generatedAt.addingTimeInterval(-3 * 86_400)
    )

    let evaluation = HealthScoreEngine.default.evaluate(report)

    #expect(evaluation.overallScore == 100)
    #expect(evaluation.overallStatus == HealthStatus.healthy)
    #expect(evaluation.topIssues.isEmpty)
}

@Test func unknownDataDoesNotScoreAsHealthy() async throws {
    let report = HealthReport.placeholder(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let evaluation = HealthScoreEngine.default.evaluate(report)

    #expect(evaluation.overallScore == 40)
    #expect(evaluation.overallStatus == .unknown)
    #expect(evaluation.scoreDisplayText == "Unknown")
    #expect(evaluation.topIssues.count == 3)
    #expect(evaluation.topIssues.allSatisfy { $0.status == .unknown })
}

@Test func warningAndCriticalStatesDegradeWeightedScore() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let report = HealthReport(
        generatedAt: generatedAt,
        storage: StorageDiagnostics(
            status: .warning,
            issues: [
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "Low free space on system volume",
                    explanation: "Available free space is below the preferred threshold."
                )
            ]
        ),
        performance: PerformanceDiagnostics(status: .healthy),
        security: SecurityDiagnostics(
            status: .critical,
            issues: [
                HealthIssue(
                    category: .security,
                    status: .critical,
                    title: "FileVault is disabled",
                    explanation: "Disk encryption is not enabled."
                )
            ]
        ),
        automation: AutomationDiagnostics(status: .healthy),
        lastMaintenanceDate: generatedAt.addingTimeInterval(-5 * 86_400)
    )

    let evaluation = HealthScoreEngine.default.evaluate(report)
    let storageComponent = try #require(evaluation.components.first { $0.category == .storage })
    let securityComponent = try #require(evaluation.components.first { $0.category == .security })

    #expect(storageComponent.rawScore == 55)
    #expect(securityComponent.rawScore == 0)
    #expect(evaluation.overallScore == 64)
    #expect(evaluation.overallStatus == .critical)
}

@Test func topThreeIssuesAreSelectedFromModelState() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let report = HealthReport(
        generatedAt: generatedAt,
        storage: StorageDiagnostics(
            status: .warning,
            issues: [
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "A Storage Warning",
                    explanation: "Storage is trending low."
                )
            ]
        ),
        performance: PerformanceDiagnostics(status: .unknown),
        security: SecurityDiagnostics(
            status: .critical,
            issues: [
                HealthIssue(
                    category: .security,
                    status: .critical,
                    title: "Critical Security Exposure",
                    explanation: "A core security control is unavailable."
                )
            ]
        ),
        automation: AutomationDiagnostics(
            status: .critical,
            issues: [
                HealthIssue(
                    category: .automation,
                    status: .critical,
                    title: "Critical Automation Failure",
                    explanation: "A required background service is failing."
                )
            ]
        ),
        lastMaintenanceDate: generatedAt.addingTimeInterval(-10 * 86_400)
    )

    let evaluation = HealthScoreEngine.default.evaluate(report)
    let titles = evaluation.topIssues.map(\.title)

    #expect(titles == [
        "Critical Security Exposure",
        "Critical Automation Failure",
        "A Storage Warning",
    ])
}

@Test func placeholderReportMarksMaintenanceUnknownWithoutHistory() async throws {
    let report = HealthReport.placeholder(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let evaluation = HealthScoreEngine.default.evaluate(report)
    let maintenance = try #require(evaluation.components.first { $0.category == .maintenance })

    #expect(maintenance.status == .unknown)
    #expect(maintenance.explanation.contains("no scan or approved maintenance timestamp recorded"))
}

@Test func successfulScanWithoutRemediationIsHealthyMaintenance() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let report = HealthReport(
        generatedAt: generatedAt,
        storage: StorageDiagnostics(status: .healthy),
        performance: PerformanceDiagnostics(status: .healthy),
        security: SecurityDiagnostics(status: .healthy),
        automation: AutomationDiagnostics(status: .healthy),
        lastReadOnlyHealthScanAt: generatedAt
    )
    let evaluation = HealthScoreEngine.default.evaluate(report)
    let maintenance = try #require(evaluation.components.first { $0.category == .maintenance })

    #expect(maintenance.status == .healthy)
    #expect(maintenance.rawScore == 100)
    #expect(evaluation.overallScore == 100)
    #expect(evaluation.overallStatus == .healthy)
    #expect(!evaluation.topIssues.contains { $0.category == .maintenance })
}

@Test func approvedMaintenanceFreshnessStillAgesCorrectly() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let report = HealthReport(
        generatedAt: generatedAt,
        storage: StorageDiagnostics(status: .healthy),
        performance: PerformanceDiagnostics(status: .healthy),
        security: SecurityDiagnostics(status: .healthy),
        automation: AutomationDiagnostics(status: .healthy),
        lastReadOnlyHealthScanAt: generatedAt,
        lastApprovedMaintenanceAt: generatedAt.addingTimeInterval(-30 * 86_400),
        lastMaintenanceSummary: "Empty Trash: Removed 3 items."
    )
    let evaluation = HealthScoreEngine.default.evaluate(report)
    let maintenance = try #require(evaluation.components.first { $0.category == .maintenance })

    #expect(maintenance.status == .warning)
    #expect(evaluation.topIssues.contains { $0.title == "Maintenance is getting stale" })
}

@Test func recommendationSerializesCleanly() async throws {
    let recommendation = MaintenanceRecommendation(
        title: "Review login items",
        explanation: "Remove login items that are no longer required.",
        riskLevel: .review,
        estimatedImpact: "May reduce background CPU and launch time overhead.",
        reversibility: "Reversible by restoring the login item.",
        relatedCategory: .automation
    )

    let encoded = try JSONEncoder().encode(recommendation)
    let decoded = try JSONDecoder().decode(MaintenanceRecommendation.self, from: encoded)

    #expect(decoded == recommendation)
}
