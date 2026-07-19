import Foundation
import SwiftUI

struct AutomationDetailsView: View {
    @Environment(AppModel.self) private var appModel

    private var automation: AutomationDiagnostics {
        appModel.currentReport.automation
    }

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 16),
        GridItem(.flexible(minimum: 220), spacing: 16),
    ]

    private var flaggedAgents: [AutomationDiagnostics.LaunchAgentRecord] {
        (automation.userLaunchAgents + automation.sharedLaunchAgents)
            .filter { !$0.findings.isEmpty }
            .sorted { lhs, rhs in
                if lhs.findings.count != rhs.findings.count {
                    return lhs.findings.count > rhs.findings.count
                }

                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
    }

    private var folderSnapshots: [AutomationDiagnostics.FolderSnapshot] {
        Array(automation.commonFolders)
    }

    var body: some View {
        GroupBox("Automation Details") {
            VStack(alignment: .leading, spacing: 16) {
                if appModel.isAnalyzing {
                    ProgressView("Inspecting LaunchAgents and automation folders…")
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    AutomationMetricLine(title: "User LaunchAgents", value: String(automation.userLaunchAgents.count))
                    AutomationMetricLine(title: "Shared LaunchAgents", value: String(automation.sharedLaunchAgents.count))
                    AutomationMetricLine(title: "System LaunchAgents", value: automation.systemLaunchAgentCount.map(String.init) ?? "Unknown")
                    AutomationMetricLine(title: "System KeepAlive", value: automation.systemKeepAliveCount.map(String.init) ?? "Unknown")
                    AutomationMetricLine(title: "Broken plists", value: String(automation.brokenPlistLabels.count))
                    AutomationMetricLine(title: "Missing executables", value: String(automation.missingExecutableLabels.count))
                    AutomationMetricLine(title: "Stale log paths", value: String(automation.staleLogPathLabels.count))
                    AutomationMetricLine(title: "KeepAlive agents", value: String(automation.keepAliveAgentLabels.count))
                    AutomationMetricLine(title: "Homebrew services", value: String(automation.homebrewServices.count))
                    AutomationMetricLine(title: "Automation folders", value: String(automation.commonFolders.filter(\.exists).count))
                }

                if !automation.issues.isEmpty {
                    issueSection
                }

                if !flaggedAgents.isEmpty {
                    flaggedAgentsSection
                }

                if !automation.keepAliveAgentLabels.isEmpty {
                    keepAliveSection
                }

                if !automation.homebrewServices.isEmpty {
                    homebrewSection
                }

                if !automation.commonFolders.isEmpty {
                    foldersSection
                }

                if !appModel.automationRecommendations.isEmpty {
                    recommendationsSection
                }

                if !automation.scanNotes.isEmpty || !automation.commandFailures.isEmpty {
                    notesSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automation Issues")
                .font(.headline)

            ForEach(automation.issues.prefix(3)) { issue in
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

    private var flaggedAgentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flagged LaunchAgents")
                .font(.headline)

            ForEach(flaggedAgents.prefix(5)) { agent in
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.label)
                        .font(.subheadline.weight(.medium))
                    Text(agent.findings.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(compactPath(agent.path))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var keepAliveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Always-On Agents")
                .font(.headline)

            ForEach(automation.keepAliveAgentLabels.prefix(6), id: \.self) { label in
                Text(label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var homebrewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Homebrew Services")
                .font(.headline)

            ForEach(automation.homebrewServices.prefix(6)) { service in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(service.name) • \(service.status)")
                        .font(.subheadline.weight(.medium))
                    if let plistPath = service.plistPath {
                        Text(plistPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automation Folders")
                .font(.headline)

            ForEach(folderSnapshots.indices, id: \.self) { index in
                let folder = folderSnapshots[index]
                AutomationFolderRow(
                    folder: folder,
                    compactPath: compactPath(folder.path)
                )
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automation Recommendations")
                .font(.headline)

            ForEach(appModel.automationRecommendations.prefix(3), id: \.title) { recommendation in
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

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automation Notes")
                .font(.headline)

            ForEach(automation.scanNotes.prefix(3)) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.operation)
                        .font(.subheadline.weight(.medium))
                    Text(note.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(compactPath(note.path))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(automation.commandFailures.prefix(2)) { failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.command)
                        .font(.subheadline.weight(.medium))
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func compactPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath) {
            return "~" + String(path.dropFirst(homePath.count))
        }

        return path
    }
}

private struct AutomationMetricLine: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
        }
    }
}

private struct AutomationFolderRow: View {
    let folder: AutomationDiagnostics.FolderSnapshot
    let compactPath: String

    private var state: String {
        if !folder.exists {
            return "Not present"
        }

        if folder.readable == false {
            return "Unreadable"
        }

        return "\(folder.itemCount ?? 0) item(s)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(folder.title) • \(state)")
                .font(.subheadline.weight(.medium))
            Text(compactPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if !folder.sampleItems.isEmpty {
                Text(folder.sampleItems.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
