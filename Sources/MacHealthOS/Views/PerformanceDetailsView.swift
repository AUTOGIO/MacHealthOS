import Foundation
import SwiftUI

struct PerformanceDetailsView: View {
    @Environment(AppModel.self) private var appModel

    private var performance: PerformanceDiagnostics {
        appModel.currentReport.performance
    }

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 16),
        GridItem(.flexible(minimum: 220), spacing: 16),
    ]

    var body: some View {
        GroupBox("Performance Details") {
            VStack(alignment: .leading, spacing: 16) {
                if appModel.isAnalyzing {
                    ProgressView("Collecting on-demand performance metrics…")
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    PerformanceMetricLine(title: "CPU load", value: PerformanceFormatters.cpuLoadString(from: performance.cpuLoadPercent))
                    PerformanceMetricLine(title: "Memory pressure", value: performance.memoryPressureSummary ?? "Unknown")
                    PerformanceMetricLine(title: "Physical memory", value: StorageFormatters.byteCountString(from: performance.physicalMemoryBytes))
                    PerformanceMetricLine(title: "Used memory", value: StorageFormatters.byteCountString(from: performance.usedMemoryBytes))
                    PerformanceMetricLine(title: "Available memory", value: StorageFormatters.byteCountString(from: performance.availableMemoryBytes))
                    PerformanceMetricLine(title: "Uptime", value: PerformanceFormatters.durationString(from: performance.uptimeSeconds))
                    PerformanceMetricLine(title: "Background services", value: performance.backgroundServiceCount.map(String.init) ?? "Unknown")
                    PerformanceMetricLine(title: "Active services", value: performance.activeBackgroundServiceCount.map(String.init) ?? "Unknown")
                    PerformanceMetricLine(title: "Enabled user services", value: String(performance.enabledUserServiceLabels.count))
                    PerformanceMetricLine(title: "Accessible login-item labels", value: String(performance.accessibleLoginItemLabels.count))
                }

                if !performance.issues.isEmpty {
                    issueSection
                }

                if !performance.topCPUProcesses.isEmpty {
                    processSection(
                        title: "Top CPU Processes",
                        processes: performance.topCPUProcesses
                    )
                }

                if !performance.topMemoryProcesses.isEmpty {
                    processSection(
                        title: "Top Memory Processes",
                        processes: performance.topMemoryProcesses
                    )
                }

                if !performance.enabledUserServiceLabels.isEmpty {
                    serviceSection(
                        title: "Startup / Background Items",
                        subtitle: "Enabled non-Apple user services exposed by launchctl in the GUI domain.",
                        labels: performance.enabledUserServiceLabels
                    )
                }

                if !performance.accessibleLoginItemLabels.isEmpty {
                    serviceSection(
                        title: "Accessible Login-Item Labels",
                        subtitle: "Only explicit login-item related labels exposed by launchctl are shown here.",
                        labels: performance.accessibleLoginItemLabels
                    )
                }

                if !appModel.performanceRecommendations.isEmpty {
                    recommendationsSection
                }

                if !performance.commandFailures.isEmpty {
                    commandFailuresSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Issues")
                .font(.headline)

            ForEach(performance.issues.prefix(3)) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(.subheadline.weight(.medium))
                    Text(issue.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Recommendations")
                .font(.headline)

            ForEach(appModel.performanceRecommendations.prefix(3), id: \.title) { recommendation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(.subheadline.weight(.medium))
                    Text(recommendation.estimatedImpact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var commandFailuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command Notes")
                .font(.headline)

            ForEach(performance.commandFailures.prefix(3)) { failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.command)
                        .font(.subheadline.weight(.medium))
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !failure.standardError.isEmpty {
                        Text(failure.standardError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func processSection(
        title: String,
        processes: [PerformanceDiagnostics.ProcessSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(processes.prefix(5)) { process in
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.command)
                        .font(.subheadline.weight(.medium))
                    Text(processDescription(process))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func serviceSection(
        title: String,
        subtitle: String,
        labels: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(labels.prefix(6), id: \.self) { label in
                Text(label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func processDescription(_ process: PerformanceDiagnostics.ProcessSnapshot) -> String {
        [
            "PID \(process.pid)",
            process.cpuPercent.map { "CPU \(PerformanceFormatters.cpuLoadString(from: $0))" },
            process.memoryPercent.map { "MEM \(StorageFormatters.percentageString(from: $0))" },
            process.residentMemoryBytes.map { "RSS \(StorageFormatters.byteCountString(from: $0))" },
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }
}

private struct PerformanceMetricLine: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
        }
    }
}
