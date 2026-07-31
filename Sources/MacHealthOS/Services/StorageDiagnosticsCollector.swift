import Foundation

struct StorageDiagnosticsCollector: Sendable {
    struct VolumeMetrics: Equatable, Sendable {
        var totalCapacityBytes: Int64?
        var freeCapacityBytes: Int64?

        var usedCapacityBytes: Int64? {
            guard
                let totalCapacityBytes,
                let freeCapacityBytes,
                totalCapacityBytes >= freeCapacityBytes
            else {
                return nil
            }

            return totalCapacityBytes - freeCapacityBytes
        }

        var freeCapacityPercent: Double? {
            guard
                let totalCapacityBytes,
                let freeCapacityBytes,
                totalCapacityBytes > 0
            else {
                return nil
            }

            return (Double(freeCapacityBytes) / Double(totalCapacityBytes)) * 100.0
        }
    }

    struct Configuration: Equatable, Sendable {
        var homeDirectoryURL: URL
        var largeFileThresholdBytes: Int64
        var oldDownloadsThresholdDays: Int
        var maximumReportedLargeFiles: Int
        var maximumReportedOldDownloads: Int
        var fixedVolumeMetrics: VolumeMetrics?

        init(
            homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
            largeFileThresholdBytes: Int64 = 1_000_000_000,
            oldDownloadsThresholdDays: Int = 30,
            maximumReportedLargeFiles: Int = 10,
            maximumReportedOldDownloads: Int = 10,
            fixedVolumeMetrics: VolumeMetrics? = nil
        ) {
            self.homeDirectoryURL = homeDirectoryURL
            self.largeFileThresholdBytes = largeFileThresholdBytes
            self.oldDownloadsThresholdDays = oldDownloadsThresholdDays
            self.maximumReportedLargeFiles = maximumReportedLargeFiles
            self.maximumReportedOldDownloads = maximumReportedOldDownloads
            self.fixedVolumeMetrics = fixedVolumeMetrics
        }
    }

    struct CollectionResult: Equatable, Sendable {
        let diagnostics: StorageDiagnostics
        let recommendations: [MaintenanceRecommendation]
    }

    private enum Thresholds {
        static let warningFreeCapacityPercent = 20.0
        static let criticalFreeCapacityPercent = 10.0
        static let warningFreeCapacityBytes: Int64 = 50 * StorageDiagnosticsCollector.gibibyte
        static let criticalFreeCapacityBytes: Int64 = 25 * StorageDiagnosticsCollector.gibibyte
        static let largeDownloadsWarningBytes: Int64 = 10 * StorageDiagnosticsCollector.gibibyte
        static let largeTrashWarningBytes: Int64 = 5 * StorageDiagnosticsCollector.gibibyte
        static let largeCachesWarningBytes: Int64 = 10 * StorageDiagnosticsCollector.gibibyte
        static let oldDownloadsWarningCount = 10
        static let oldDownloadsWarningBytes: Int64 = 5 * StorageDiagnosticsCollector.gibibyte
        static let largeFilesWarningCount = 5
        static let largeFilesWarningBytes: Int64 = 20 * StorageDiagnosticsCollector.gibibyte
    }

    private static let gibibyte: Int64 = 1_073_741_824

    private static let excludedDirectoryNames: Set<String> = [
        ".git", "node_modules", "DerivedData", ".build", "Pods", ".cache", "dist", "vendor", ".venv"
    ]

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func collect(now: Date = Date()) -> CollectionResult {
        let homeDirectoryURL = configuration.homeDirectoryURL.standardizedFileURL
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads", isDirectory: true)
        let trashURL = homeDirectoryURL.appendingPathComponent(".Trash", isDirectory: true)
        let cachesURL = homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)

        var scanErrors: [StorageDiagnostics.ScanError] = []
        let volumeMetrics = collectVolumeMetrics(for: homeDirectoryURL, scanErrors: &scanErrors)
        let downloadsSizeBytes = directorySize(at: downloadsURL, operation: "Downloads size scan", scanErrors: &scanErrors)
        let trashSizeBytes = directorySize(at: trashURL, operation: "Trash size scan", scanErrors: &scanErrors)
        let cachesSizeBytes = directorySize(at: cachesURL, operation: "Caches size scan", scanErrors: &scanErrors)
        let largeFiles = largeFiles(in: homeDirectoryURL, scanErrors: &scanErrors)
        let oldDownloads = oldDownloads(in: downloadsURL, now: now, scanErrors: &scanErrors)

        let issues = storageIssues(
            volumeMetrics: volumeMetrics,
            downloadsSizeBytes: downloadsSizeBytes,
            trashSizeBytes: trashSizeBytes,
            cachesSizeBytes: cachesSizeBytes,
            largeFiles: largeFiles,
            oldDownloads: oldDownloads,
            scanErrors: scanErrors
        )

        let diagnostics = StorageDiagnostics(
            status: storageStatus(from: issues),
            totalCapacityBytes: volumeMetrics.totalCapacityBytes,
            usedCapacityBytes: volumeMetrics.usedCapacityBytes,
            freeCapacityBytes: volumeMetrics.freeCapacityBytes,
            freeCapacityPercent: volumeMetrics.freeCapacityPercent,
            downloadsSizeBytes: downloadsSizeBytes,
            trashSizeBytes: trashSizeBytes,
            cachesSizeBytes: cachesSizeBytes,
            largeFileThresholdBytes: configuration.largeFileThresholdBytes,
            oldDownloadsThresholdDays: configuration.oldDownloadsThresholdDays,
            largeFiles: largeFiles,
            oldDownloads: oldDownloads,
            scanErrors: scanErrors,
            issues: issues
        )

        return CollectionResult(
            diagnostics: diagnostics,
            recommendations: storageRecommendations(for: diagnostics)
        )
    }

    private func collectVolumeMetrics(
        for homeDirectoryURL: URL,
        scanErrors: inout [StorageDiagnostics.ScanError]
    ) -> VolumeMetrics {
        if let fixedVolumeMetrics = configuration.fixedVolumeMetrics {
            return fixedVolumeMetrics
        }

        do {
            let values = try homeDirectoryURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
            ])

            let totalCapacityBytes = values.volumeTotalCapacity.map(Int64.init)
            let freeCapacityBytes: Int64?
            if let importantUsageCapacity = values.volumeAvailableCapacityForImportantUsage {
                freeCapacityBytes = Int64(importantUsageCapacity)
            } else if let availableCapacity = values.volumeAvailableCapacity {
                freeCapacityBytes = Int64(availableCapacity)
            } else {
                freeCapacityBytes = nil
            }

            return VolumeMetrics(
                totalCapacityBytes: totalCapacityBytes,
                freeCapacityBytes: freeCapacityBytes
            )
        } catch {
            scanErrors.append(
                StorageDiagnostics.ScanError(
                    path: homeDirectoryURL.path,
                    operation: "Volume capacity scan",
                    message: error.localizedDescription
                )
            )

            return VolumeMetrics(totalCapacityBytes: nil, freeCapacityBytes: nil)
        }
    }

    private func directorySize(
        at url: URL,
        operation: String,
        scanErrors: inout [StorageDiagnostics.ScanError]
    ) -> Int64? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]

        var localErrors: [StorageDiagnostics.ScanError] = []

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { fileURL, error in
                localErrors.append(
                    StorageDiagnostics.ScanError(
                        path: fileURL.path,
                        operation: operation,
                        message: error.localizedDescription
                    )
                )
                return true
            }
        ) else {
            scanErrors.append(
                StorageDiagnostics.ScanError(
                    path: url.path,
                    operation: operation,
                    message: "Enumerator could not be created."
                )
            )
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: keys)

                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }

                if values.isRegularFile == true {
                    totalSize += Int64(values.fileSize ?? 0)
                }
            } catch {
                localErrors.append(
                    StorageDiagnostics.ScanError(
                        path: fileURL.path,
                        operation: operation,
                        message: error.localizedDescription
                    )
                )
            }
        }

        scanErrors.append(contentsOf: localErrors)
        return localErrors.isEmpty ? totalSize : nil
    }

    private func largeFiles(
        in homeDirectoryURL: URL,
        scanErrors: inout [StorageDiagnostics.ScanError]
    ) -> [StorageDiagnostics.FileFinding] {
        let topLevelKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        let topLevelEntries: [URL]
        do {
            topLevelEntries = try FileManager.default.contentsOfDirectory(
                at: homeDirectoryURL,
                includingPropertiesForKeys: topLevelKeys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            scanErrors.append(
                StorageDiagnostics.ScanError(
                    path: homeDirectoryURL.path,
                    operation: "Large file scan",
                    message: error.localizedDescription
                )
            )
            return []
        }

        var findings: [StorageDiagnostics.FileFinding] = []

        for entryURL in topLevelEntries {
            do {
                let values = try entryURL.resourceValues(forKeys: Set(topLevelKeys))

                if values.isSymbolicLink == true || values.isHidden == true {
                    continue
                }

                if entryURL.lastPathComponent == "Library" || StorageDiagnosticsCollector.excludedDirectoryNames.contains(entryURL.lastPathComponent) {
                    continue
                }

                if values.isRegularFile == true {
                    if let finding = makeFinding(for: entryURL, resourceValues: values) {
                        findings.append(finding)
                    }
                    continue
                }

                guard values.isDirectory == true else {
                    continue
                }

                findings.append(contentsOf: largeFilesInsideDirectory(entryURL, scanErrors: &scanErrors))
            } catch {
                scanErrors.append(
                    StorageDiagnostics.ScanError(
                        path: entryURL.path,
                        operation: "Large file scan",
                        message: error.localizedDescription
                    )
                )
            }
        }

        return findings
            .sorted { lhs, rhs in
                largeFileSort(lhs: lhs, rhs: rhs)
            }
            .prefix(configuration.maximumReportedLargeFiles)
            .map { $0 }
    }

    private func largeFilesInsideDirectory(
        _ rootURL: URL,
        scanErrors: inout [StorageDiagnostics.ScanError]
    ) -> [StorageDiagnostics.FileFinding] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        var localErrors: [StorageDiagnostics.ScanError] = []

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { fileURL, error in
                localErrors.append(
                    StorageDiagnostics.ScanError(
                        path: fileURL.path,
                        operation: "Large file scan",
                        message: error.localizedDescription
                    )
                )
                return true
            }
        ) else {
            scanErrors.append(
                StorageDiagnostics.ScanError(
                    path: rootURL.path,
                    operation: "Large file scan",
                    message: "Enumerator could not be created."
                )
            )
            return []
        }

        var findings: [StorageDiagnostics.FileFinding] = []
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: keys)

                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }

                if values.isDirectory == true {
                    if StorageDiagnosticsCollector.excludedDirectoryNames.contains(fileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                        continue
                    }
                }

                if values.isRegularFile == true, let finding = makeFinding(for: fileURL, resourceValues: values) {
                    findings.append(finding)
                }
            } catch {
                localErrors.append(
                    StorageDiagnostics.ScanError(
                        path: fileURL.path,
                        operation: "Large file scan",
                        message: error.localizedDescription
                    )
                )
            }
        }

        scanErrors.append(contentsOf: localErrors)
        return findings
    }

    private func oldDownloads(
        in downloadsURL: URL,
        now: Date,
        scanErrors: inout [StorageDiagnostics.ScanError]
    ) -> [StorageDiagnostics.FileFinding] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: downloadsURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -configuration.oldDownloadsThresholdDays,
            to: now
        ) ?? now

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        var localErrors: [StorageDiagnostics.ScanError] = []

        guard let enumerator = FileManager.default.enumerator(
            at: downloadsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { fileURL, error in
                localErrors.append(
                    StorageDiagnostics.ScanError(
                        path: fileURL.path,
                        operation: "Old Downloads scan",
                        message: error.localizedDescription
                    )
                )
                return true
            }
        ) else {
            scanErrors.append(
                StorageDiagnostics.ScanError(
                    path: downloadsURL.path,
                    operation: "Old Downloads scan",
                    message: "Enumerator could not be created."
                )
            )
            return []
        }

        var findings: [StorageDiagnostics.FileFinding] = []
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: keys)

                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }

                guard values.isRegularFile == true else {
                    continue
                }

                guard let contentModificationDate = values.contentModificationDate, contentModificationDate < cutoffDate else {
                    continue
                }

                findings.append(
                    StorageDiagnostics.FileFinding(
                        path: fileURL.path,
                        sizeBytes: Int64(values.fileSize ?? 0),
                        contentModificationDate: contentModificationDate
                    )
                )
            } catch {
                localErrors.append(
                    StorageDiagnostics.ScanError(
                        path: fileURL.path,
                        operation: "Old Downloads scan",
                        message: error.localizedDescription
                    )
                )
            }
        }

        scanErrors.append(contentsOf: localErrors)
        return findings
            .sorted {
                if $0.contentModificationDate != $1.contentModificationDate {
                    return ($0.contentModificationDate ?? .distantFuture) < ($1.contentModificationDate ?? .distantFuture)
                }

                if $0.sizeBytes != $1.sizeBytes {
                    return $0.sizeBytes > $1.sizeBytes
                }

                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
            .prefix(configuration.maximumReportedOldDownloads)
            .map { $0 }
    }

    private func storageIssues(
        volumeMetrics: VolumeMetrics,
        downloadsSizeBytes: Int64?,
        trashSizeBytes: Int64?,
        cachesSizeBytes: Int64?,
        largeFiles: [StorageDiagnostics.FileFinding],
        oldDownloads: [StorageDiagnostics.FileFinding],
        scanErrors: [StorageDiagnostics.ScanError]
    ) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        let unavailableMetrics = unavailableMetricNames(
            volumeMetrics: volumeMetrics,
            downloadsSizeBytes: downloadsSizeBytes,
            trashSizeBytes: trashSizeBytes,
            cachesSizeBytes: cachesSizeBytes
        )

        if !unavailableMetrics.isEmpty {
            issues.append(
                HealthIssue(
                    category: .storage,
                    status: .unknown,
                    title: "Some storage metrics are unavailable",
                    explanation: "Unavailable metrics: \(unavailableMetrics.joined(separator: ", "))."
                )
            )
        }

        if !scanErrors.isEmpty {
            let scanPaths = Array(scanErrors.map(\.path).prefix(3)).joined(separator: ", ")
            issues.append(
                HealthIssue(
                    category: .storage,
                    status: .unknown,
                    title: "Some storage paths could not be scanned",
                    explanation: "Read-only storage checks were partial. Affected paths include: \(scanPaths)."
                )
            )
        }

        if let freeCapacityBytes = volumeMetrics.freeCapacityBytes, let freeCapacityPercent = volumeMetrics.freeCapacityPercent {
            if freeCapacityPercent < Thresholds.criticalFreeCapacityPercent || freeCapacityBytes < Thresholds.criticalFreeCapacityBytes {
                issues.append(
                    HealthIssue(
                        category: .storage,
                        status: .critical,
                        title: "Free disk space is critically low",
                        explanation: "Only \(StorageFormatters.byteCountString(from: freeCapacityBytes)) is free (\(StorageFormatters.percentageString(from: freeCapacityPercent)))."
                    )
                )
            } else if freeCapacityPercent < Thresholds.warningFreeCapacityPercent || freeCapacityBytes < Thresholds.warningFreeCapacityBytes {
                issues.append(
                    HealthIssue(
                        category: .storage,
                        status: .warning,
                        title: "Free disk space is getting low",
                        explanation: "Only \(StorageFormatters.byteCountString(from: freeCapacityBytes)) is free (\(StorageFormatters.percentageString(from: freeCapacityPercent)))."
                    )
                )
            }
        }

        if let downloadsSizeBytes, downloadsSizeBytes >= Thresholds.largeDownloadsWarningBytes {
            issues.append(
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "Downloads is using significant space",
                    explanation: "~/Downloads is currently using \(StorageFormatters.byteCountString(from: downloadsSizeBytes))."
                )
            )
        }

        if let trashSizeBytes, trashSizeBytes >= Thresholds.largeTrashWarningBytes {
            issues.append(
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "Trash contains significant reclaimable space",
                    explanation: "~/.Trash is currently using \(StorageFormatters.byteCountString(from: trashSizeBytes))."
                )
            )
        }

        if let cachesSizeBytes, cachesSizeBytes >= Thresholds.largeCachesWarningBytes {
            issues.append(
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "Caches are using significant space",
                    explanation: "~/Library/Caches is currently using \(StorageFormatters.byteCountString(from: cachesSizeBytes))."
                )
            )
        }

        let largeFilesTotalBytes = largeFiles.reduce(into: Int64.zero) { $0 += $1.sizeBytes }
        if !largeFiles.isEmpty && (
            largeFiles.count >= Thresholds.largeFilesWarningCount ||
            largeFilesTotalBytes >= Thresholds.largeFilesWarningBytes
        ) {
            issues.append(
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "Several large files were found in the home folder",
                    explanation: "\(largeFiles.count) file(s) above \(StorageFormatters.byteCountString(from: configuration.largeFileThresholdBytes)) were found in visible home directories."
                )
            )
        }

        let oldDownloadsTotalBytes = oldDownloads.reduce(into: Int64.zero) { $0 += $1.sizeBytes }
        if !oldDownloads.isEmpty && (
            oldDownloads.count >= Thresholds.oldDownloadsWarningCount ||
            oldDownloadsTotalBytes >= Thresholds.oldDownloadsWarningBytes
        ) {
            issues.append(
                HealthIssue(
                    category: .storage,
                    status: .warning,
                    title: "Downloads contains many old files",
                    explanation: "\(oldDownloads.count) old file(s) were found in ~/Downloads using \(StorageFormatters.byteCountString(from: oldDownloadsTotalBytes))."
                )
            )
        }

        return issues
    }

    private func storageRecommendations(for diagnostics: StorageDiagnostics) -> [MaintenanceRecommendation] {
        var recommendations: [MaintenanceRecommendation] = []

        let freeCapacityLow = diagnostics.issues.contains {
            $0.title == "Free disk space is getting low" || $0.title == "Free disk space is critically low"
        }
        let oldDownloadsBytes = diagnostics.oldDownloads.reduce(into: Int64.zero) { $0 += $1.sizeBytes }
        let largeFilesBytes = diagnostics.largeFiles.reduce(into: Int64.zero) { $0 += $1.sizeBytes }

        if freeCapacityLow {
            let reviewBytes = max(0, oldDownloadsBytes + largeFilesBytes + (diagnostics.trashSizeBytes ?? 0))
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review major storage consumers",
                    explanation: "Start with Downloads, Trash, and the largest visible files in the home folder before changing anything else.",
                    riskLevel: .review,
                    estimatedImpact: "Could help recover visibility over \(StorageFormatters.byteCountString(from: reviewBytes)).",
                    reversibility: "Review is non-destructive. Any later cleanup remains a manual decision.",
                    relatedCategory: .storage
                )
            )
        }

        if !diagnostics.largeFiles.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review files above \(StorageFormatters.byteCountString(from: diagnostics.largeFileThresholdBytes))",
                    explanation: "Large files were found in visible home directories. Confirm whether they still need to remain on the primary disk.",
                    riskLevel: .review,
                    estimatedImpact: "Potentially affects \(StorageFormatters.byteCountString(from: largeFilesBytes)) across \(diagnostics.largeFiles.count) file(s).",
                    reversibility: "Review is non-destructive. Manual archiving or relocation is reversible if copies are retained.",
                    relatedCategory: .storage
                )
            )
        }

        if !diagnostics.oldDownloads.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review old Downloads files",
                    explanation: "Older files were found in ~/Downloads beyond the configured age threshold.",
                    riskLevel: .review,
                    estimatedImpact: "Potentially affects \(StorageFormatters.byteCountString(from: oldDownloadsBytes)) across \(diagnostics.oldDownloads.count) file(s).",
                    reversibility: "Review is non-destructive. Files can be archived or left in place.",
                    relatedCategory: .storage
                )
            )
        }

        if let trashSizeBytes = diagnostics.trashSizeBytes, trashSizeBytes > 0 {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Inspect Trash contents",
                    explanation: "Trash is consuming local storage. Confirm whether any items need to be restored before clearing them manually.",
                    riskLevel: .review,
                    estimatedImpact: "Trash currently holds \(StorageFormatters.byteCountString(from: trashSizeBytes)).",
                    reversibility: "Items remain restorable until the user empties Trash.",
                    relatedCategory: .storage
                )
            )
        }

        if let cachesSizeBytes = diagnostics.cachesSizeBytes, cachesSizeBytes >= Thresholds.largeCachesWarningBytes {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Inspect oversized caches",
                    explanation: "Some app caches may be large enough to deserve inspection, but cache removal should remain deliberate and app-aware.",
                    riskLevel: .advanced,
                    estimatedImpact: "~/Library/Caches is using \(StorageFormatters.byteCountString(from: cachesSizeBytes)).",
                    reversibility: "Many caches rebuild automatically, but some apps may need to re-download or re-index data.",
                    relatedCategory: .storage
                )
            )
        }

        if !diagnostics.scanErrors.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review inaccessible storage paths",
                    explanation: "Some requested home-safe paths could not be fully scanned. Resolve access problems before trusting the storage picture completely.",
                    riskLevel: .safe,
                    estimatedImpact: "Improves confidence in the storage assessment rather than reclaiming space directly.",
                    reversibility: "Read-only review only.",
                    relatedCategory: .storage
                )
            )
        }

        return recommendations
    }

    private func storageStatus(from issues: [HealthIssue]) -> HealthStatus {
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

    private func unavailableMetricNames(
        volumeMetrics: VolumeMetrics,
        downloadsSizeBytes: Int64?,
        trashSizeBytes: Int64?,
        cachesSizeBytes: Int64?
    ) -> [String] {
        var missingNames: [String] = []

        if volumeMetrics.totalCapacityBytes == nil {
            missingNames.append("total disk capacity")
        }

        if volumeMetrics.usedCapacityBytes == nil {
            missingNames.append("used disk space")
        }

        if volumeMetrics.freeCapacityBytes == nil {
            missingNames.append("free disk space")
        }

        if volumeMetrics.freeCapacityPercent == nil {
            missingNames.append("free disk percentage")
        }

        if downloadsSizeBytes == nil {
            missingNames.append("~/Downloads size")
        }

        if trashSizeBytes == nil {
            missingNames.append("~/.Trash size")
        }

        if cachesSizeBytes == nil {
            missingNames.append("~/Library/Caches size")
        }

        return missingNames
    }

    private func makeFinding(for url: URL, resourceValues: URLResourceValues) -> StorageDiagnostics.FileFinding? {
        let sizeBytes = Int64(resourceValues.fileSize ?? 0)
        guard sizeBytes > configuration.largeFileThresholdBytes else {
            return nil
        }

        return StorageDiagnostics.FileFinding(
            path: url.path,
            sizeBytes: sizeBytes,
            contentModificationDate: resourceValues.contentModificationDate
        )
    }

    private func largeFileSort(lhs: StorageDiagnostics.FileFinding, rhs: StorageDiagnostics.FileFinding) -> Bool {
        if lhs.sizeBytes != rhs.sizeBytes {
            return lhs.sizeBytes > rhs.sizeBytes
        }

        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }
}
