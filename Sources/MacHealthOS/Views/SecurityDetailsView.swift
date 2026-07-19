import Foundation
import SwiftUI

struct SecurityDetailsView: View {
    @Environment(AppModel.self) private var appModel

    private var security: SecurityDiagnostics {
        appModel.currentReport.security
    }

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 16),
        GridItem(.flexible(minimum: 220), spacing: 16),
    ]

    var body: some View {
        GroupBox("Security Details") {
            VStack(alignment: .leading, spacing: 16) {
                if appModel.isAnalyzing {
                    ProgressView("Collecting read-only security metrics…")
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    SecurityMetricLine(title: "Gatekeeper", value: SecurityFormatters.enabledStatusString(from: security.gatekeeperEnabled))
                    SecurityMetricLine(title: "FileVault", value: SecurityFormatters.enabledStatusString(from: security.fileVaultEnabled))
                    SecurityMetricLine(title: "SIP", value: SecurityFormatters.enabledStatusString(from: security.systemIntegrityProtectionEnabled))
                    SecurityMetricLine(title: "Firewall", value: SecurityFormatters.enabledStatusString(from: security.firewallEnabled))
                    SecurityMetricLine(title: "macOS version", value: security.macOSVersion ?? "Unknown")
                    SecurityMetricLine(
                        title: "Software Update",
                        value: SecurityFormatters.updateStatusString(
                            count: security.pendingSecurityUpdatesCount,
                            labels: security.availableSecurityUpdateLabels
                        )
                    )
                    SecurityMetricLine(title: "XProtect payload", value: security.xProtectPayload?.version ?? "Unknown")
                    SecurityMetricLine(title: "XProtect config", value: security.xProtectConfigData?.version ?? "Unknown")
                }

                if !security.issues.isEmpty {
                    issueSection
                }

                if security.xProtectPayload != nil || security.xProtectConfigData != nil {
                    xProtectSection
                }

                if !security.availableSecurityUpdateLabels.isEmpty {
                    updatesSection
                }

                if !appModel.securityRecommendations.isEmpty {
                    recommendationsSection
                }

                if !security.commandFailures.isEmpty {
                    commandFailuresSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Security Issues")
                .font(.headline)

            ForEach(security.issues.prefix(3)) { issue in
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

    private var xProtectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("XProtect Packages")
                .font(.headline)

            if let xProtectPayload = security.xProtectPayload {
                packageLine(title: "Payload", package: xProtectPayload)
            }

            if let xProtectConfigData = security.xProtectConfigData {
                packageLine(title: "Config Data", package: xProtectConfigData)
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Updates")
                .font(.headline)

            ForEach(security.availableSecurityUpdateLabels.prefix(5), id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Security Recommendations")
                .font(.headline)

            ForEach(appModel.securityRecommendations.prefix(3), id: \.title) { recommendation in
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

            ForEach(security.commandFailures.prefix(3)) { failure in
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

    private func packageLine(
        title: String,
        package: SecurityDiagnostics.PackageReceipt
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(package.version)")
                .font(.subheadline.weight(.medium))
            Text(package.packageIdentifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("Installed \(StorageFormatters.dateString(from: package.installDate))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SecurityMetricLine: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
        }
    }
}
