import Foundation
import SwiftUI

struct StorageDetailsView: View {
    @Environment(AppModel.self) private var appModel

    private var storage: StorageDiagnostics {
        appModel.currentReport.storage
    }

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 16),
        GridItem(.flexible(minimum: 220), spacing: 16),
    ]

    var body: some View {
        GroupBox("Storage Details") {
            VStack(alignment: .leading, spacing: 16) {
                if appModel.isAnalyzing {
                    ProgressView("Analyzing home-safe storage paths…")
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    MetricLine(title: "Total capacity", value: StorageFormatters.byteCountString(from: storage.totalCapacityBytes))
                    MetricLine(title: "Used space", value: StorageFormatters.byteCountString(from: storage.usedCapacityBytes))
                    MetricLine(title: "Free space", value: StorageFormatters.byteCountString(from: storage.freeCapacityBytes))
                    MetricLine(title: "Free percentage", value: StorageFormatters.percentageString(from: storage.freeCapacityPercent))
                    MetricLine(title: "Downloads size", value: StorageFormatters.byteCountString(from: storage.downloadsSizeBytes))
                    MetricLine(title: "Trash size", value: StorageFormatters.byteCountString(from: storage.trashSizeBytes))
                    MetricLine(title: "Caches size", value: StorageFormatters.byteCountString(from: storage.cachesSizeBytes))
                    MetricLine(title: "Large file threshold", value: StorageFormatters.byteCountString(from: storage.largeFileThresholdBytes))
                    MetricLine(title: "Old Downloads threshold", value: "\(storage.oldDownloadsThresholdDays) days")
                }

                if !storage.issues.isEmpty {
                    storageIssueSection
                }

                if !storage.largeFiles.isEmpty {
                    fileSection(
                        title: "Large Files",
                        subtitle: "Visible home files above \(StorageFormatters.byteCountString(from: storage.largeFileThresholdBytes))",
                        files: storage.largeFiles
                    )
                }

                if !storage.oldDownloads.isEmpty {
                    fileSection(
                        title: "Old Downloads Files",
                        subtitle: "Downloads files older than \(storage.oldDownloadsThresholdDays) days",
                        files: storage.oldDownloads
                    )
                }

                if !appModel.storageRecommendations.isEmpty {
                    recommendationsSection
                }

                if !storage.scanErrors.isEmpty {
                    scanErrorsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var storageIssueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage Issues")
                .font(.headline)

            ForEach(storage.issues.prefix(3)) { issue in
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
            Text("Storage Recommendations")
                .font(.headline)

            ForEach(appModel.storageRecommendations.prefix(3), id: \.title) { recommendation in
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

    private var scanErrorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan Access Notes")
                .font(.headline)

            ForEach(storage.scanErrors.prefix(3)) { scanError in
                VStack(alignment: .leading, spacing: 2) {
                    Text(compactPath(scanError.path))
                        .font(.subheadline.weight(.medium))
                    Text("\(scanError.operation): \(scanError.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fileSection(
        title: String,
        subtitle: String,
        files: [StorageDiagnostics.FileFinding]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(files.prefix(5)) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName(from: file.path))
                        .font(.subheadline.weight(.medium))
                    Text(compactPath(file.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(StorageFormatters.byteCountString(from: file.sizeBytes)) • Modified \(StorageFormatters.dateString(from: file.contentModificationDate))")
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

    private func fileName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

private struct MetricLine: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
        }
    }
}
