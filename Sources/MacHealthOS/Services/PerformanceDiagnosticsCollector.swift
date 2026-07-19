import Darwin
import Foundation

struct PerformanceDiagnosticsCollector: Sendable {
    struct Configuration: Sendable {
        var commandTimeout: TimeInterval
        var maximumReportedProcesses: Int
        var maximumReportedServiceLabels: Int
        var fixedPhysicalMemoryBytes: Int64?
        var fixedUptimeSeconds: TimeInterval?
        var userID: Int?

        init(
            commandTimeout: TimeInterval = 5.0,
            maximumReportedProcesses: Int = 5,
            maximumReportedServiceLabels: Int = 8,
            fixedPhysicalMemoryBytes: Int64? = nil,
            fixedUptimeSeconds: TimeInterval? = nil,
            userID: Int? = nil
        ) {
            self.commandTimeout = commandTimeout
            self.maximumReportedProcesses = maximumReportedProcesses
            self.maximumReportedServiceLabels = maximumReportedServiceLabels
            self.fixedPhysicalMemoryBytes = fixedPhysicalMemoryBytes
            self.fixedUptimeSeconds = fixedUptimeSeconds
            self.userID = userID
        }
    }

    struct CollectionResult: Equatable, Sendable {
        let diagnostics: PerformanceDiagnostics
        let recommendations: [MaintenanceRecommendation]
    }

    private struct TopSummary: Sendable {
        let cpuLoadPercent: Double?
        let usedMemoryBytes: Int64?
    }

    private struct MemorySnapshot: Sendable {
        let availableBytes: Int64?
        let compressedBytes: Int64?
    }

    private struct MemoryPressureAssessment: Sendable {
        let status: HealthStatus?
        let summary: String?
    }

    private struct LaunchctlSnapshot: Sendable {
        let serviceCount: Int?
        let activeServiceCount: Int?
        let enabledUserServiceLabels: [String]
        let accessibleLoginItemLabels: [String]
    }

    private enum ProcessSort {
        case cpu
        case memory
    }

    private enum Thresholds {
        static let warningCPULoadPercent = 75.0
        static let criticalCPULoadPercent = 90.0
        static let warningAvailableMemoryPercent = 6.0
        static let criticalAvailableMemoryPercent = 2.0
        static let warningCompressedMemoryPercent = 20.0
        static let criticalCompressedMemoryPercent = 30.0
        static let warningUptimeDays = 14.0
        static let criticalUptimeDays = 45.0
        static let warningEnabledUserServicesCount = 12
    }

    private static let kibibyte: Int64 = 1024

    let configuration: Configuration
    private let commandRunner: any CommandRunning

    init(
        configuration: Configuration = Configuration(),
        commandRunner: any CommandRunning = SafeCommandRunner()
    ) {
        self.configuration = configuration
        self.commandRunner = commandRunner
    }

    func collect(now _: Date = Date()) -> CollectionResult {
        let physicalMemoryBytes = configuration.fixedPhysicalMemoryBytes ?? currentPhysicalMemoryBytes()
        let uptimeSeconds = configuration.fixedUptimeSeconds ?? ProcessInfo.processInfo.systemUptime

        var commandFailures: [PerformanceDiagnostics.CommandFailure] = []
        let topSummary = collectTopSummary(commandFailures: &commandFailures)
        let memorySnapshot = collectMemorySnapshot(commandFailures: &commandFailures)
        let topCPUProcesses = collectProcesses(sortedBy: .cpu, commandFailures: &commandFailures)
        let topMemoryProcesses = collectProcesses(sortedBy: .memory, commandFailures: &commandFailures)
        let launchctlSnapshot = collectLaunchctlSnapshot(commandFailures: &commandFailures)
        let memoryPressureAssessment = assessMemoryPressure(
            snapshot: memorySnapshot,
            physicalMemoryBytes: physicalMemoryBytes
        )

        var diagnostics = PerformanceDiagnostics(
            status: .unknown,
            cpuLoadPercent: topSummary?.cpuLoadPercent,
            memoryPressureSummary: memoryPressureAssessment.summary,
            physicalMemoryBytes: physicalMemoryBytes,
            usedMemoryBytes: topSummary?.usedMemoryBytes,
            availableMemoryBytes: memorySnapshot?.availableBytes,
            uptimeSeconds: uptimeSeconds,
            topCPUProcesses: topCPUProcesses,
            topMemoryProcesses: topMemoryProcesses,
            accessibleLoginItemLabels: launchctlSnapshot?.accessibleLoginItemLabels ?? [],
            enabledUserServiceLabels: launchctlSnapshot?.enabledUserServiceLabels ?? [],
            backgroundServiceCount: launchctlSnapshot?.serviceCount,
            activeBackgroundServiceCount: launchctlSnapshot?.activeServiceCount,
            commandFailures: commandFailures,
            issues: []
        )

        let issues = performanceIssues(
            diagnostics: diagnostics,
            memoryPressureStatus: memoryPressureAssessment.status
        )
        diagnostics.status = performanceStatus(from: issues)
        diagnostics.issues = issues

        return CollectionResult(
            diagnostics: diagnostics,
            recommendations: performanceRecommendations(for: diagnostics)
        )
    }

    private func collectTopSummary(
        commandFailures: inout [PerformanceDiagnostics.CommandFailure]
    ) -> TopSummary? {
        let result = commandRunner.run(
            .top,
            arguments: ["-l", "1", "-n", "0"],
            timeout: configuration.commandTimeout
        )

        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return nil
        }

        return parseTopSummary(result.standardOutput)
    }

    private func collectMemorySnapshot(
        commandFailures: inout [PerformanceDiagnostics.CommandFailure]
    ) -> MemorySnapshot? {
        let result = commandRunner.run(
            .vmStat,
            arguments: [],
            timeout: configuration.commandTimeout
        )

        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return nil
        }

        return parseMemorySnapshot(result.standardOutput)
    }

    private func collectProcesses(
        sortedBy sort: ProcessSort,
        commandFailures: inout [PerformanceDiagnostics.CommandFailure]
    ) -> [PerformanceDiagnostics.ProcessSnapshot] {
        let arguments: [String]
        switch sort {
        case .cpu:
            arguments = ["-Aceo", "pid=,pcpu=,pmem=,rss=,comm=", "-r"]
        case .memory:
            arguments = ["-Aceo", "pid=,pmem=,rss=,pcpu=,comm=", "-r"]
        }

        let result = commandRunner.run(
            .ps,
            arguments: arguments,
            timeout: configuration.commandTimeout
        )

        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return []
        }

        return parseProcessList(result.standardOutput, sortedBy: sort)
    }

    private func collectLaunchctlSnapshot(
        commandFailures: inout [PerformanceDiagnostics.CommandFailure]
    ) -> LaunchctlSnapshot? {
        let userID = configuration.userID ?? Int(getuid())
        let result = commandRunner.run(
            .launchctl,
            arguments: ["print", "gui/\(userID)"],
            timeout: configuration.commandTimeout
        )

        guard result.succeeded else {
            commandFailures.append(commandFailure(from: result))
            return nil
        }

        return parseLaunchctlSnapshot(result.standardOutput)
    }

    private func performanceIssues(
        diagnostics: PerformanceDiagnostics,
        memoryPressureStatus: HealthStatus?
    ) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        let unavailableMetrics = unavailableMetricNames(diagnostics: diagnostics)
        if !unavailableMetrics.isEmpty {
            issues.append(
                HealthIssue(
                    category: .performance,
                    status: .unknown,
                    title: "Some performance metrics are unavailable",
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
                    category: .performance,
                    status: .unknown,
                    title: "Some performance commands failed",
                    explanation: "Failed commands: \(failedCommands). See command notes for details."
                )
            )
        }

        if let memoryPressureStatus {
            switch memoryPressureStatus {
            case .critical:
                issues.append(
                    HealthIssue(
                        category: .performance,
                        status: .critical,
                        title: "Memory pressure is high",
                        explanation: diagnostics.memoryPressureSummary ?? "Current memory pressure could not be summarized."
                    )
                )
            case .warning:
                issues.append(
                    HealthIssue(
                        category: .performance,
                        status: .warning,
                        title: "Memory pressure is elevated",
                        explanation: diagnostics.memoryPressureSummary ?? "Current memory pressure could not be summarized."
                    )
                )
            case .healthy, .unknown:
                break
            }
        }

        if let cpuLoadPercent = diagnostics.cpuLoadPercent {
            if cpuLoadPercent >= Thresholds.criticalCPULoadPercent {
                issues.append(
                    HealthIssue(
                        category: .performance,
                        status: .critical,
                        title: "CPU load is critically high",
                        explanation: "Observed CPU load was \(PerformanceFormatters.cpuLoadString(from: cpuLoadPercent)) during the on-demand sample."
                    )
                )
            } else if cpuLoadPercent >= Thresholds.warningCPULoadPercent {
                issues.append(
                    HealthIssue(
                        category: .performance,
                        status: .warning,
                        title: "CPU load is elevated",
                        explanation: "Observed CPU load was \(PerformanceFormatters.cpuLoadString(from: cpuLoadPercent)) during the on-demand sample."
                    )
                )
            }
        }

        if let uptimeSeconds = diagnostics.uptimeSeconds {
            let uptimeDays = uptimeSeconds / 86_400
            if uptimeDays >= Thresholds.criticalUptimeDays {
                issues.append(
                    HealthIssue(
                        category: .performance,
                        status: .critical,
                        title: "System uptime is very long",
                        explanation: "The Mac has been up for \(PerformanceFormatters.durationString(from: uptimeSeconds))."
                    )
                )
            } else if uptimeDays >= Thresholds.warningUptimeDays {
                issues.append(
                    HealthIssue(
                        category: .performance,
                        status: .warning,
                        title: "System uptime is long",
                        explanation: "The Mac has been up for \(PerformanceFormatters.durationString(from: uptimeSeconds))."
                    )
                )
            }
        }

        if diagnostics.enabledUserServiceLabels.count >= Thresholds.warningEnabledUserServicesCount {
            issues.append(
                HealthIssue(
                    category: .performance,
                    status: .warning,
                    title: "Many user background services are enabled",
                    explanation: "\(diagnostics.enabledUserServiceLabels.count) non-Apple user services are enabled in the GUI domain."
                )
            )
        }

        return issues
    }

    private func performanceRecommendations(
        for diagnostics: PerformanceDiagnostics
    ) -> [MaintenanceRecommendation] {
        var recommendations: [MaintenanceRecommendation] = []

        if diagnostics.issues.contains(where: { $0.title == "Memory pressure is high" || $0.title == "Memory pressure is elevated" }) {
            let topProcesses = diagnostics.topMemoryProcesses
                .prefix(3)
                .map(\.command)
                .joined(separator: ", ")
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review memory-heavy apps",
                    explanation: "The current snapshot shows elevated memory pressure. Review the heaviest processes before changing anything else.",
                    riskLevel: .review,
                    estimatedImpact: topProcesses.isEmpty
                        ? "Could reduce compression and reclaim RAM headroom."
                        : "Likely first review targets: \(topProcesses).",
                    reversibility: "Read-only review only.",
                    relatedCategory: .performance
                )
            )
        }

        if let uptimeSeconds = diagnostics.uptimeSeconds, uptimeSeconds / 86_400 >= Thresholds.warningUptimeDays {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Plan a restart window",
                    explanation: "Prolonged uptime can leave background state and memory fragmentation in place longer than needed.",
                    riskLevel: .review,
                    estimatedImpact: "A restart can reset accumulated runtime state after \(PerformanceFormatters.durationString(from: uptimeSeconds)).",
                    reversibility: "Fully reversible. Only run it when the user is ready.",
                    relatedCategory: .performance
                )
            )
        }

        if diagnostics.enabledUserServiceLabels.count >= Thresholds.warningEnabledUserServicesCount {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review startup and background services",
                    explanation: "A relatively large set of non-Apple user services is enabled in the GUI domain.",
                    riskLevel: .review,
                    estimatedImpact: "\(diagnostics.enabledUserServiceLabels.count) enabled user services detected; explicit login-item labels exposed: \(diagnostics.accessibleLoginItemLabels.count).",
                    reversibility: "Review is non-destructive. Any later change remains manual.",
                    relatedCategory: .performance
                )
            )
        }

        if !diagnostics.commandFailures.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review incomplete performance scan",
                    explanation: "One or more read-only performance commands failed or timed out.",
                    riskLevel: .safe,
                    estimatedImpact: "Improves confidence in CPU, memory, and service results rather than changing the system directly.",
                    reversibility: "Read-only review only.",
                    relatedCategory: .performance
                )
            )
        }

        return recommendations
    }

    private func performanceStatus(from issues: [HealthIssue]) -> HealthStatus {
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

    private func unavailableMetricNames(diagnostics: PerformanceDiagnostics) -> [String] {
        var names: [String] = []

        if diagnostics.cpuLoadPercent == nil {
            names.append("CPU load")
        }

        if diagnostics.memoryPressureSummary == nil {
            names.append("memory pressure")
        }

        if diagnostics.physicalMemoryBytes == nil {
            names.append("physical memory")
        }

        if diagnostics.usedMemoryBytes == nil {
            names.append("used memory")
        }

        if diagnostics.uptimeSeconds == nil {
            names.append("uptime")
        }

        if diagnostics.topCPUProcesses.isEmpty {
            names.append("top CPU processes")
        }

        if diagnostics.topMemoryProcesses.isEmpty {
            names.append("top memory processes")
        }

        if diagnostics.backgroundServiceCount == nil || diagnostics.activeBackgroundServiceCount == nil {
            names.append("background services summary")
        }

        return names
    }

    private func currentPhysicalMemoryBytes() -> Int64? {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        guard physicalMemory <= UInt64(Int64.max) else {
            return nil
        }

        return Int64(physicalMemory)
    }

    private func commandFailure(
        from result: SafeCommandRunner.ExecutionResult
    ) -> PerformanceDiagnostics.CommandFailure {
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

        return PerformanceDiagnostics.CommandFailure(
            command: result.command.displayName,
            arguments: result.arguments,
            message: message,
            standardError: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func parseTopSummary(_ output: String) -> TopSummary? {
        var cpuLoadPercent: Double?
        var usedMemoryBytes: Int64?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("CPU usage:") {
                cpuLoadPercent = parseCPULoad(from: line)
            } else if line.hasPrefix("PhysMem:") {
                usedMemoryBytes = parseUsedMemory(from: line)
            }
        }

        guard cpuLoadPercent != nil || usedMemoryBytes != nil else {
            return nil
        }

        return TopSummary(cpuLoadPercent: cpuLoadPercent, usedMemoryBytes: usedMemoryBytes)
    }

    private func parseCPULoad(from line: String) -> Double? {
        let components = line
            .replacingOccurrences(of: "CPU usage:", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var userPercent: Double?
        var systemPercent: Double?
        var idlePercent: Double?

        for component in components {
            let parts = component.split(separator: " ", omittingEmptySubsequences: true)
            guard
                parts.count >= 2,
                let percentageToken = parts.first?.replacingOccurrences(of: "%", with: ""),
                let percentage = Double(percentageToken)
            else {
                continue
            }

            switch parts[1] {
            case "user":
                userPercent = percentage
            case "sys":
                systemPercent = percentage
            case "idle":
                idlePercent = percentage
            default:
                continue
            }
        }

        if let userPercent, let systemPercent {
            return userPercent + systemPercent
        }

        if let idlePercent {
            return max(0, 100.0 - idlePercent)
        }

        return nil
    }

    private func parseUsedMemory(from line: String) -> Int64? {
        guard let physMemRange = line.range(of: "PhysMem:") else {
            return nil
        }

        let remainder = line[physMemRange.upperBound...]
            .trimmingCharacters(in: .whitespaces)
        guard let usedToken = remainder.split(separator: " ").first else {
            return nil
        }

        return parseByteToken(String(usedToken))
    }

    private func parseMemorySnapshot(_ output: String) -> MemorySnapshot? {
        var pageSizeBytes: Int64?
        var freePages: Int64?
        var speculativePages: Int64?
        var purgeablePages: Int64?
        var compressedPages: Int64?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("Mach Virtual Memory Statistics:") {
                pageSizeBytes = parsePageSize(from: line)
                continue
            }

            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            let key = parts[0].replacingOccurrences(of: "\"", with: "")
            let value = parseIntegerValue(parts[1])

            switch key {
            case "Pages free":
                freePages = value
            case "Pages speculative":
                speculativePages = value
            case "Pages purgeable":
                purgeablePages = value
            case "Pages occupied by compressor":
                compressedPages = value
            default:
                continue
            }
        }

        guard let pageSizeBytes else {
            return nil
        }

        let availablePages = [freePages, speculativePages, purgeablePages]
            .compactMap { $0 }
            .reduce(0, +)
        let availableBytes =
            (freePages != nil || speculativePages != nil || purgeablePages != nil)
            ? availablePages * pageSizeBytes
            : nil
        let compressedBytes = compressedPages.map { $0 * pageSizeBytes }

        return MemorySnapshot(availableBytes: availableBytes, compressedBytes: compressedBytes)
    }

    private func parsePageSize(from line: String) -> Int64? {
        guard
            let startRange = line.range(of: "page size of "),
            let endRange = line.range(of: " bytes")
        else {
            return nil
        }

        let value = line[startRange.upperBound..<endRange.lowerBound]
        return Int64(value)
    }

    private func parseIntegerValue(_ rawValue: String) -> Int64? {
        let digits = rawValue.filter(\.isNumber)
        return Int64(digits)
    }

    private func assessMemoryPressure(
        snapshot: MemorySnapshot?,
        physicalMemoryBytes: Int64?
    ) -> MemoryPressureAssessment {
        guard let snapshot, let physicalMemoryBytes, physicalMemoryBytes > 0 else {
            return MemoryPressureAssessment(status: nil, summary: nil)
        }

        let availablePercent = snapshot.availableBytes.map {
            (Double($0) / Double(physicalMemoryBytes)) * 100.0
        }
        let compressedPercent = snapshot.compressedBytes.map {
            (Double($0) / Double(physicalMemoryBytes)) * 100.0
        }

        let status: HealthStatus?
        if
            let availablePercent, availablePercent < Thresholds.criticalAvailableMemoryPercent ||
            (compressedPercent ?? 0) >= Thresholds.criticalCompressedMemoryPercent
        {
            status = .critical
        } else if
            let availablePercent, availablePercent < Thresholds.warningAvailableMemoryPercent ||
            (compressedPercent ?? 0) >= Thresholds.warningCompressedMemoryPercent
        {
            status = .warning
        } else if availablePercent != nil || compressedPercent != nil {
            status = .healthy
        } else {
            status = nil
        }

        guard let status else {
            return MemoryPressureAssessment(status: nil, summary: nil)
        }

        var parts: [String] = [status.displayName]
        if let availablePercent {
            parts.append("\(StorageFormatters.percentageString(from: availablePercent)) available")
        }
        if let compressedBytes = snapshot.compressedBytes {
            parts.append("\(StorageFormatters.byteCountString(from: compressedBytes)) compressed")
        }

        return MemoryPressureAssessment(
            status: status,
            summary: parts.joined(separator: " • ")
        )
    }

    private func parseProcessList(
        _ output: String,
        sortedBy sort: ProcessSort
    ) -> [PerformanceDiagnostics.ProcessSnapshot] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let fields = rawLine.split(
                    maxSplits: 4,
                    omittingEmptySubsequences: true,
                    whereSeparator: \.isWhitespace
                )

                guard fields.count == 5, let pid = Int(fields[0]) else {
                    return nil
                }

                let command = String(fields[4])
                switch sort {
                case .cpu:
                    return PerformanceDiagnostics.ProcessSnapshot(
                        pid: pid,
                        command: command,
                        cpuPercent: Double(fields[1]),
                        memoryPercent: Double(fields[2]),
                        residentMemoryBytes: Int64(fields[3]).map { $0 * Self.kibibyte }
                    )
                case .memory:
                    return PerformanceDiagnostics.ProcessSnapshot(
                        pid: pid,
                        command: command,
                        cpuPercent: Double(fields[3]),
                        memoryPercent: Double(fields[1]),
                        residentMemoryBytes: Int64(fields[2]).map { $0 * Self.kibibyte }
                    )
                }
            }
            .prefix(configuration.maximumReportedProcesses)
            .map { $0 }
    }

    private func parseLaunchctlSnapshot(_ output: String) -> LaunchctlSnapshot? {
        var serviceCount: Int?
        var activeServiceCount: Int?
        var enabledUserServiceLabels: [String] = []
        var accessibleLoginItemLabels: [String] = []
        var insideDisabledServicesBlock = false

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("service count = ") {
                serviceCount = Int(line.replacingOccurrences(of: "service count = ", with: ""))
                continue
            }

            if line.hasPrefix("active service count = ") {
                activeServiceCount = Int(line.replacingOccurrences(of: "active service count = ", with: ""))
                continue
            }

            if line == "disabled services = {" {
                insideDisabledServicesBlock = true
                continue
            }

            if insideDisabledServicesBlock {
                if line == "}" {
                    insideDisabledServicesBlock = false
                    continue
                }

                guard let separatorRange = line.range(of: "=>") else {
                    continue
                }

                let label = line[..<separatorRange.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                let state = line[separatorRange.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard state == "enabled", isUserManagedServiceLabel(label) else {
                    continue
                }

                enabledUserServiceLabels.append(label)
                if labelContainsExplicitLoginItemMarker(label) {
                    accessibleLoginItemLabels.append(label)
                }
            }
        }

        enabledUserServiceLabels.sort { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        accessibleLoginItemLabels.sort { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        guard
            serviceCount != nil ||
            activeServiceCount != nil ||
            !enabledUserServiceLabels.isEmpty ||
            !accessibleLoginItemLabels.isEmpty
        else {
            return nil
        }

        return LaunchctlSnapshot(
            serviceCount: serviceCount,
            activeServiceCount: activeServiceCount,
            enabledUserServiceLabels: Array(enabledUserServiceLabels.prefix(configuration.maximumReportedServiceLabels)),
            accessibleLoginItemLabels: Array(accessibleLoginItemLabels.prefix(configuration.maximumReportedServiceLabels))
        )
    }

    private func isUserManagedServiceLabel(_ label: String) -> Bool {
        !(label.hasPrefix("com.apple.") || label.hasPrefix("application.com.apple."))
    }

    private func labelContainsExplicitLoginItemMarker(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return lowered.contains("login-item") || lowered.contains("loginitem")
    }

    private func parseByteToken(_ rawToken: String) -> Int64? {
        let trimmedToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unit = trimmedToken.last else {
            return nil
        }

        let numberPortion = trimmedToken.dropLast()
        guard let value = Double(numberPortion) else {
            return nil
        }

        let multiplier: Double
        switch unit {
        case "K":
            multiplier = 1_024
        case "M":
            multiplier = 1_048_576
        case "G":
            multiplier = 1_073_741_824
        case "T":
            multiplier = 1_099_511_627_776
        default:
            return nil
        }

        return Int64((value * multiplier).rounded())
    }
}
