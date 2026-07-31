import Foundation
import Testing
@testable import MacHealthOS

@Test func reportStoreWritesMarkdownAndJSONPair() async throws {
    let homeDirectoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: homeDirectoryURL)
    }

    try FileManager.default.createDirectory(at: homeDirectoryURL, withIntermediateDirectories: true)

    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000.456)
    let report = HealthReport(
        generatedAt: generatedAt,
        machine: MachineProfile(
            machineName: "Test Mac",
            macOSVersion: "macOS 26.6",
            hardwareArchitecture: "arm64"
        ),
        storage: StorageDiagnostics(
            status: .warning,
            totalCapacityBytes: 500 * 1_073_741_824,
            freeCapacityBytes: 40 * 1_073_741_824,
            issues: [
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "Low free space on system volume",
                    explanation: "Available free space is below the preferred threshold."
                )
            ]
        ),
        performance: PerformanceDiagnostics(status: .healthy, cpuLoadPercent: 22.0),
        security: SecurityDiagnostics(status: .healthy, macOSVersion: "macOS 26.6"),
        automation: AutomationDiagnostics(status: .warning, keepAliveAgentLabels: ["com.example.agent"]),
        recommendations: [
            MaintenanceRecommendation(
                title: "Review login items",
                explanation: "Too many background items are enabled.",
                riskLevel: .review,
                estimatedImpact: "May reduce background load.",
                reversibility: "Manual and reversible.",
                relatedCategory: .automation
            )
        ],
        maintenanceActions: [
            MaintenanceActionRecord(
                kind: .openDownloadsFolder,
                timestamp: generatedAt,
                title: "Open Downloads Folder",
                explanation: "Opened Downloads in Finder.",
                riskLevel: .safe,
                estimatedImpact: "Manual review only.",
                reversibility: "Fully reversible.",
                result: .opened,
                details: "Opened Downloads in Finder for manual review."
            )
        ],
        aiExplanation: AIExplanation(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100.123),
            provider: .ollama,
            disclaimer: "AI explanation is advisory. System facts come from local diagnostics.",
            normalConditions: [
                "Performance is healthy."
            ],
            realRisks: [
                "Available free space is below the preferred threshold."
            ],
            expectedBehavior: [
                "Background items can exist without indicating a fault."
            ],
            unknownOrUnavailable: [],
            recommendedNextSteps: [
                "Review login items."
            ]
        ),
        lastStatusMessage: "Report generated."
    )

    let store = ReportStore(
        configuration: .init(homeDirectoryURL: homeDirectoryURL)
    )

    let files = try store.writeReport(report: report)

    #expect(FileManager.default.fileExists(atPath: files.markdownURL.path))
    #expect(FileManager.default.fileExists(atPath: files.jsonURL.path))
    #expect(files.markdownURL.lastPathComponent.hasPrefix("mac_health_os_2023-11-14_"))
    #expect(files.markdownURL.pathExtension == "md")
    #expect(files.jsonURL.lastPathComponent.hasPrefix("mac_health_os_2023-11-14_"))
    #expect(files.jsonURL.pathExtension == "json")

    let markdown = try String(contentsOf: files.markdownURL, encoding: .utf8)
    #expect(markdown.contains("Machine Name: Test Mac"))
    #expect(markdown.contains("Hardware Architecture: arm64"))
    #expect(markdown.contains("Health Score"))
    #expect(markdown.contains("Maintenance Action Log"))
    #expect(markdown.contains("## AI Explanation (Advisory)"))
    #expect(markdown.contains("### Normal Conditions"))
    #expect(markdown.contains("Performance is healthy."))
    #expect(markdown.contains("### Real Risks"))
    #expect(markdown.contains("Available free space is below the preferred threshold."))

    let jsonObject = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: files.jsonURL)) as? [String: Any])
    #expect(jsonObject["schemaVersion"] as? Int == 2)
    let reportObject = try #require(jsonObject["report"] as? [String: Any])
    #expect((reportObject["generatedAt"] as? String)?.contains(".") == true)
    let aiExplanationObject = try #require(reportObject["aiExplanation"] as? [String: Any])
    #expect(aiExplanationObject["provider"] as? String == "ollama")
    #expect((aiExplanationObject["normalConditions"] as? [String]) == ["Performance is healthy."])
    #expect((aiExplanationObject["realRisks"] as? [String]) == ["Available free space is below the preferred threshold."])

    let latestFiles = try store.latestReportFiles()
    let resolvedLatestFiles = try #require(latestFiles)
    #expect(resolvedLatestFiles.markdownURL.standardizedFileURL == files.markdownURL.standardizedFileURL)
    #expect(resolvedLatestFiles.jsonURL.standardizedFileURL == files.jsonURL.standardizedFileURL)
}

@Test func reportStoreWritesSparseRuntimeStyleReport() async throws {
    let homeDirectoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: homeDirectoryURL)
    }

    try FileManager.default.createDirectory(at: homeDirectoryURL, withIntermediateDirectories: true)

    let report = HealthReport(
        generatedAt: Date(timeIntervalSince1970: 1_782_466_469.573),
        machine: MachineProfile(
            machineName: "Eduardo’s MacBook Air",
            macOSVersion: "Version 26.6 (Build 25G5043d)",
            hardwareArchitecture: "arm64"
        ),
        lastStatusMessage: "Ready. No checks have been run yet."
    )

    let store = ReportStore(
        configuration: .init(homeDirectoryURL: homeDirectoryURL)
    )

    let files = try store.writeReport(report: report)

    #expect(FileManager.default.fileExists(atPath: files.jsonURL.path))
    let markdown = try String(contentsOf: files.markdownURL, encoding: .utf8)
    #expect(!markdown.contains("## AI Explanation (Advisory)"))

    let jsonObject = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: files.jsonURL)) as? [String: Any])
    let reportObject = try #require(jsonObject["report"] as? [String: Any])
    #expect(reportObject["generatedAt"] as? String == "2026-06-26T09:34:29.573Z")
    #expect(reportObject["aiExplanation"] is NSNull || reportObject["aiExplanation"] == nil)
}
