import Foundation

struct AutomationDiagnosticsCollector: Sendable {
    struct FolderTarget: Equatable, Sendable {
        let title: String
        let url: URL
    }

    struct Configuration: Sendable {
        var homeDirectoryURL: URL
        var sharedLaunchAgentsURL: URL
        var systemLaunchAgentsURL: URL
        var commonFolders: [FolderTarget]
        var commandTimeout: TimeInterval
        var maximumReportedAgentFindings: Int
        var maximumReportedSystemLabels: Int
        var maximumReportedFolderSamples: Int
        var maximumReportedHomebrewServices: Int

        init(
            homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
            sharedLaunchAgentsURL: URL = URL(fileURLWithPath: "/Library/LaunchAgents"),
            systemLaunchAgentsURL: URL = URL(fileURLWithPath: "/System/Library/LaunchAgents"),
            commonFolders: [FolderTarget]? = nil,
            commandTimeout: TimeInterval = 5.0,
            maximumReportedAgentFindings: Int = 10,
            maximumReportedSystemLabels: Int = 8,
            maximumReportedFolderSamples: Int = 6,
            maximumReportedHomebrewServices: Int = 8
        ) {
            self.homeDirectoryURL = homeDirectoryURL
            self.sharedLaunchAgentsURL = sharedLaunchAgentsURL
            self.systemLaunchAgentsURL = systemLaunchAgentsURL
            self.commonFolders = commonFolders ?? [
                FolderTarget(title: "Automation", url: homeDirectoryURL.appendingPathComponent("Automation", isDirectory: true)),
                FolderTarget(title: "GitHub", url: homeDirectoryURL.appendingPathComponent("Documents/GitHub", isDirectory: true)),
                FolderTarget(title: "Shortcuts", url: homeDirectoryURL.appendingPathComponent("Library/Shortcuts", isDirectory: true)),
                FolderTarget(title: "Scripts", url: homeDirectoryURL.appendingPathComponent("Library/Scripts", isDirectory: true)),
                FolderTarget(title: "Reports", url: homeDirectoryURL.appendingPathComponent("Reports", isDirectory: true)),
            ]
            self.commandTimeout = commandTimeout
            self.maximumReportedAgentFindings = maximumReportedAgentFindings
            self.maximumReportedSystemLabels = maximumReportedSystemLabels
            self.maximumReportedFolderSamples = maximumReportedFolderSamples
            self.maximumReportedHomebrewServices = maximumReportedHomebrewServices
        }

        var userLaunchAgentsURL: URL {
            homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("LaunchAgents", isDirectory: true)
        }
    }

    struct CollectionResult: Equatable, Sendable {
        let diagnostics: AutomationDiagnostics
        let recommendations: [MaintenanceRecommendation]
    }

    private struct DirectoryScanResult: Sendable {
        let records: [AutomationDiagnostics.LaunchAgentRecord]
        let brokenPlistLabels: [String]
        let missingExecutableLabels: [String]
        let staleLogPathLabels: [String]
        let keepAliveAgentLabels: [String]
        let scanNotes: [AutomationDiagnostics.ScanNote]
        let commandFailures: [AutomationDiagnostics.CommandFailure]
    }

    private struct SystemMetadataResult: Sendable {
        let count: Int?
        let keepAliveCount: Int?
        let sampleLabels: [String]
        let scanNotes: [AutomationDiagnostics.ScanNote]
    }

    private enum Thresholds {
        static let warningKeepAliveAgents = 5
    }

    let configuration: Configuration
    private let commandRunner: any CommandRunning

    init(
        configuration: Configuration = Configuration(),
        commandRunner: any CommandRunning = SafeCommandRunner()
    ) {
        self.configuration = configuration
        self.commandRunner = commandRunner
    }

    func collect() -> CollectionResult {
        let userScan = scanLaunchAgents(
            at: configuration.userLaunchAgentsURL,
            domain: .user,
            lintPlists: true
        )
        let sharedScan = scanLaunchAgents(
            at: configuration.sharedLaunchAgentsURL,
            domain: .shared,
            lintPlists: true
        )
        let systemMetadata = scanSystemLaunchAgentMetadata(at: configuration.systemLaunchAgentsURL)
        let commonFolders = scanCommonFolders()
        let homebrewServices = collectHomebrewServices()

        var diagnostics = AutomationDiagnostics(
            status: .unknown,
            userLaunchAgents: userScan.records,
            sharedLaunchAgents: sharedScan.records,
            systemLaunchAgentCount: systemMetadata.count,
            systemKeepAliveCount: systemMetadata.keepAliveCount,
            systemSampleLabels: systemMetadata.sampleLabels,
            commonFolders: commonFolders.snapshots,
            homebrewServices: homebrewServices.services,
            brokenPlistLabels: Array((userScan.brokenPlistLabels + sharedScan.brokenPlistLabels).uniquedPreservingOrder()),
            missingExecutableLabels: Array((userScan.missingExecutableLabels + sharedScan.missingExecutableLabels).uniquedPreservingOrder()),
            staleLogPathLabels: Array((userScan.staleLogPathLabels + sharedScan.staleLogPathLabels).uniquedPreservingOrder()),
            keepAliveAgentLabels: Array((userScan.keepAliveAgentLabels + sharedScan.keepAliveAgentLabels).uniquedPreservingOrder()),
            commandFailures: userScan.commandFailures + sharedScan.commandFailures + homebrewServices.commandFailures,
            scanNotes: userScan.scanNotes + sharedScan.scanNotes + systemMetadata.scanNotes + commonFolders.scanNotes,
            issues: []
        )

        let issues = automationIssues(for: diagnostics)
        diagnostics.status = automationStatus(from: issues)
        diagnostics.issues = issues

        return CollectionResult(
            diagnostics: diagnostics,
            recommendations: automationRecommendations(for: diagnostics)
        )
    }

    private func scanLaunchAgents(
        at directoryURL: URL,
        domain: AutomationDiagnostics.LaunchAgentDomain,
        lintPlists: Bool
    ) -> DirectoryScanResult {
        var scanNotes: [AutomationDiagnostics.ScanNote] = []
        var commandFailures: [AutomationDiagnostics.CommandFailure] = []

        let plistURLs = plistFiles(in: directoryURL, operation: "LaunchAgents scan", scanNotes: &scanNotes)
        let records = plistURLs.compactMap { plistURL -> AutomationDiagnostics.LaunchAgentRecord? in
            let lintResult = lintPlists
                ? lintPlist(at: plistURL, commandFailures: &commandFailures)
                : .notRequested
            let lintValid: Bool?
            switch lintResult {
            case .notRequested:
                lintValid = nil
            case .valid:
                lintValid = true
            case .invalid(let message):
                scanNotes.append(
                    AutomationDiagnostics.ScanNote(
                        path: plistURL.path,
                        operation: "Plist validation",
                        message: message
                    )
                )
                lintValid = false
            }

            guard let plist = loadPlist(at: plistURL, operation: "Plist parse", scanNotes: &scanNotes) else {
                return AutomationDiagnostics.LaunchAgentRecord(
                    path: plistURL.path,
                    label: plistURL.deletingPathExtension().lastPathComponent,
                    domain: domain,
                    lintValid: lintValid,
                    keepAlive: false,
                    runAtLoad: nil,
                    executablePath: nil,
                    executableExists: nil,
                    standardOutPath: nil,
                    standardOutParentExists: nil,
                    standardErrorPath: nil,
                    standardErrorParentExists: nil,
                    findings: lintValid == false ? ["Invalid plist structure"] : []
                )
            }

            let label = (plist["Label"] as? String) ?? plistURL.deletingPathExtension().lastPathComponent
            let keepAlive = keepAliveValue(from: plist["KeepAlive"])
            let runAtLoad = plist["RunAtLoad"] as? Bool
            let executablePath = executablePath(from: plist)
            let executableExists = executablePath.map { fileExists(atPath: $0) }
            let standardOutPath = plist["StandardOutPath"] as? String
            let standardOutParentExists = standardOutPath.map(parentDirectoryExists(for:))
            let standardErrorPath = plist["StandardErrorPath"] as? String
            let standardErrorParentExists = standardErrorPath.map(parentDirectoryExists(for:))

            var findings: [String] = []
            if lintValid == false {
                findings.append("Invalid plist")
            }
            if let executablePath, executableExists == false {
                findings.append("Missing executable")
                scanNotes.append(
                    AutomationDiagnostics.ScanNote(
                        path: plistURL.path,
                        operation: "Executable check",
                        message: "\(label) points to a missing executable: \(executablePath)"
                    )
                )
            }
            if let executablePath, !executablePath.hasPrefix("/") {
                findings.append("Non-absolute executable path")
            }
            if let standardOutPath, standardOutParentExists == false {
                findings.append("Missing stdout log folder")
                scanNotes.append(
                    AutomationDiagnostics.ScanNote(
                        path: plistURL.path,
                        operation: "Log path check",
                        message: "\(label) uses a missing stdout parent directory: \(standardOutPath)"
                    )
                )
            }
            if let standardErrorPath, standardErrorParentExists == false {
                findings.append("Missing stderr log folder")
                scanNotes.append(
                    AutomationDiagnostics.ScanNote(
                        path: plistURL.path,
                        operation: "Log path check",
                        message: "\(label) uses a missing stderr parent directory: \(standardErrorPath)"
                    )
                )
            }
            if keepAlive {
                findings.append("KeepAlive")
            }

            return AutomationDiagnostics.LaunchAgentRecord(
                path: plistURL.path,
                label: label,
                domain: domain,
                lintValid: lintPlists ? lintValid : nil,
                keepAlive: keepAlive,
                runAtLoad: runAtLoad,
                executablePath: executablePath,
                executableExists: executableExists,
                standardOutPath: standardOutPath,
                standardOutParentExists: standardOutParentExists,
                standardErrorPath: standardErrorPath,
                standardErrorParentExists: standardErrorParentExists,
                findings: findings
            )
        }

        return DirectoryScanResult(
            records: records,
            brokenPlistLabels: records.filter { $0.lintValid == false }.map(\.label),
            missingExecutableLabels: records.filter { $0.executablePath != nil && $0.executableExists == false }.map(\.label),
            staleLogPathLabels: records.filter {
                ($0.standardOutPath != nil && $0.standardOutParentExists == false) ||
                ($0.standardErrorPath != nil && $0.standardErrorParentExists == false)
            }.map(\.label),
            keepAliveAgentLabels: records.filter(\.keepAlive).map(\.label),
            scanNotes: scanNotes,
            commandFailures: commandFailures
        )
    }

    private func scanSystemLaunchAgentMetadata(at directoryURL: URL) -> SystemMetadataResult {
        var scanNotes: [AutomationDiagnostics.ScanNote] = []
        let plistURLs = plistFiles(
            in: directoryURL,
            operation: "System LaunchAgents metadata",
            scanNotes: &scanNotes
        )

        var keepAliveCount = 0
        var labels: [String] = []

        for plistURL in plistURLs {
            guard let plist = loadPlist(at: plistURL, operation: "System LaunchAgent parse", scanNotes: &scanNotes) else {
                continue
            }

            let label = (plist["Label"] as? String) ?? plistURL.deletingPathExtension().lastPathComponent
            labels.append(label)
            if keepAliveValue(from: plist["KeepAlive"]) {
                keepAliveCount += 1
            }
        }

        let sampleLabels = labels
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .prefix(configuration.maximumReportedSystemLabels)
            .map { $0 }

        return SystemMetadataResult(
            count: plistURLs.isEmpty ? nil : plistURLs.count,
            keepAliveCount: plistURLs.isEmpty ? nil : keepAliveCount,
            sampleLabels: sampleLabels,
            scanNotes: scanNotes
        )
    }

    private func scanCommonFolders() -> (snapshots: [AutomationDiagnostics.FolderSnapshot], scanNotes: [AutomationDiagnostics.ScanNote]) {
        var snapshots: [AutomationDiagnostics.FolderSnapshot] = []
        var scanNotes: [AutomationDiagnostics.ScanNote] = []

        for folder in configuration.commonFolders {
            let path = folder.url.path
            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                snapshots.append(
                    AutomationDiagnostics.FolderSnapshot(
                        title: folder.title,
                        path: path,
                        exists: false,
                        readable: nil,
                        itemCount: nil,
                        sampleItems: []
                    )
                )
                continue
            }

            do {
                let entries = try FileManager.default.contentsOfDirectory(
                    at: folder.url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                let sampleItems = entries
                    .map(\.lastPathComponent)
                    .sorted { lhs, rhs in
                        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                    }
                    .prefix(configuration.maximumReportedFolderSamples)
                    .map { $0 }

                snapshots.append(
                    AutomationDiagnostics.FolderSnapshot(
                        title: folder.title,
                        path: path,
                        exists: true,
                        readable: true,
                        itemCount: entries.count,
                        sampleItems: sampleItems
                    )
                )
            } catch {
                scanNotes.append(
                    AutomationDiagnostics.ScanNote(
                        path: path,
                        operation: "Folder metadata",
                        message: error.localizedDescription
                    )
                )
                snapshots.append(
                    AutomationDiagnostics.FolderSnapshot(
                        title: folder.title,
                        path: path,
                        exists: true,
                        readable: false,
                        itemCount: nil,
                        sampleItems: []
                    )
                )
            }
        }

        return (snapshots, scanNotes)
    }

    private func collectHomebrewServices() -> (services: [AutomationDiagnostics.HomebrewService], commandFailures: [AutomationDiagnostics.CommandFailure]) {
        guard homebrewExists() else {
            return ([], [])
        }

        let result = commandRunner.run(
            .brew,
            arguments: ["services", "list"],
            timeout: configuration.commandTimeout
        )

        guard result.succeeded else {
            return ([], [commandFailure(from: result)])
        }

        let services = combinedOutput(from: result)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { parseHomebrewServiceLine(String($0)) }
            .prefix(configuration.maximumReportedHomebrewServices)
            .map { $0 }

        return (services, [])
    }

    private func automationIssues(for diagnostics: AutomationDiagnostics) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        let unavailableMetrics = unavailableMetricNames(diagnostics: diagnostics)
        if !unavailableMetrics.isEmpty {
            issues.append(
                HealthIssue(
                    category: .automation,
                    status: .unknown,
                    title: "Some automation locations are unavailable",
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
                    category: .automation,
                    status: .unknown,
                    title: "Some automation commands failed",
                    explanation: "Failed commands: \(failedCommands). See automation notes for details."
                )
            )
        }

        if !diagnostics.brokenPlistLabels.isEmpty {
            issues.append(
                HealthIssue(
                    category: .automation,
                    status: .warning,
                    title: "Some LaunchAgent files are invalid",
                    explanation: "\(diagnostics.brokenPlistLabels.count) plist file(s) failed validation: \(diagnostics.brokenPlistLabels.prefix(3).joined(separator: ", "))."
                )
            )
        }

        if !diagnostics.missingExecutableLabels.isEmpty {
            issues.append(
                HealthIssue(
                    category: .automation,
                    status: .warning,
                    title: "Some LaunchAgents point to missing apps or scripts",
                    explanation: "\(diagnostics.missingExecutableLabels.count) LaunchAgent(s) reference executables that were not found."
                )
            )
        }

        if !diagnostics.staleLogPathLabels.isEmpty {
            issues.append(
                HealthIssue(
                    category: .automation,
                    status: .warning,
                    title: "Some LaunchAgents use missing log folders",
                    explanation: "\(diagnostics.staleLogPathLabels.count) LaunchAgent(s) write logs into folders that do not currently exist."
                )
            )
        }

        if diagnostics.keepAliveAgentLabels.count >= Thresholds.warningKeepAliveAgents {
            issues.append(
                HealthIssue(
                    category: .automation,
                    status: .warning,
                    title: "Several automation agents are configured to stay running",
                    explanation: "\(diagnostics.keepAliveAgentLabels.count) LaunchAgent(s) use KeepAlive, which can make the background setup harder to reason about."
                )
            )
        }

        let problematicHomebrewServices = diagnostics.homebrewServices.filter { homebrewServiceNeedsAttention($0) }
        if !problematicHomebrewServices.isEmpty {
            issues.append(
                HealthIssue(
                    category: .automation,
                    status: .warning,
                    title: "Some Homebrew services need review",
                    explanation: "Homebrew services with non-standard status: \(problematicHomebrewServices.prefix(3).map(\.name).joined(separator: ", "))."
                )
            )
        }

        return issues
    }

    private func automationRecommendations(
        for diagnostics: AutomationDiagnostics
    ) -> [MaintenanceRecommendation] {
        var recommendations: [MaintenanceRecommendation] = []

        if !diagnostics.brokenPlistLabels.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review invalid background item files",
                    explanation: "Some LaunchAgent plist files could not be validated. Open the affected files or the apps that installed them before trusting those automations.",
                    riskLevel: .review,
                    estimatedImpact: "Could restore predictability for \(diagnostics.brokenPlistLabels.count) background item(s).",
                    reversibility: "Review only. No changes are made by this app.",
                    relatedCategory: .automation
                )
            )
        }

        if !diagnostics.missingExecutableLabels.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review startup items that point to removed apps or scripts",
                    explanation: "Some background items appear to reference executables that are no longer present.",
                    riskLevel: .review,
                    estimatedImpact: "Could reduce launch-time failures for \(diagnostics.missingExecutableLabels.count) item(s).",
                    reversibility: "Review only. Any cleanup remains a manual decision.",
                    relatedCategory: .automation
                )
            )
        }

        if !diagnostics.staleLogPathLabels.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review background items with outdated log destinations",
                    explanation: "Some background items write to folders that do not currently exist, which can hide failures or make troubleshooting harder.",
                    riskLevel: .review,
                    estimatedImpact: "Improves visibility for \(diagnostics.staleLogPathLabels.count) item(s).",
                    reversibility: "Review only. Any later path change is manual.",
                    relatedCategory: .automation
                )
            )
        }

        if diagnostics.keepAliveAgentLabels.count >= Thresholds.warningKeepAliveAgents {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review always-on background items",
                    explanation: "Several LaunchAgents are configured to keep restarting or staying alive. Confirm each one is still needed.",
                    riskLevel: .review,
                    estimatedImpact: "Applies to \(diagnostics.keepAliveAgentLabels.count) always-on background item(s).",
                    reversibility: "Review only. No background item is removed or reloaded by this app.",
                    relatedCategory: .automation
                )
            )
        }

        let problematicHomebrewServices = diagnostics.homebrewServices.filter { homebrewServiceNeedsAttention($0) }
        if !problematicHomebrewServices.isEmpty {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review Homebrew services that are not in a normal state",
                    explanation: "One or more Homebrew-managed services reported a non-standard status.",
                    riskLevel: .review,
                    estimatedImpact: "Affects \(problematicHomebrewServices.count) Homebrew service(s).",
                    reversibility: "Review only. No service is started, stopped, loaded, or unloaded here.",
                    relatedCategory: .automation
                )
            )
        }

        if diagnostics.issues.contains(where: { $0.status == .unknown }) {
            recommendations.append(
                MaintenanceRecommendation(
                    title: "Review incomplete automation visibility",
                    explanation: "Some automation folders or checks were unreadable or partially unavailable.",
                    riskLevel: .safe,
                    estimatedImpact: "Improves confidence in the background-item picture rather than changing the system directly.",
                    reversibility: "Read-only review only.",
                    relatedCategory: .automation
                )
            )
        }

        return recommendations
    }

    private func automationStatus(from issues: [HealthIssue]) -> HealthStatus {
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

    private func unavailableMetricNames(diagnostics: AutomationDiagnostics) -> [String] {
        var names: [String] = []

        if diagnostics.systemLaunchAgentCount == nil {
            names.append("system LaunchAgents metadata")
        }

        if diagnostics.commonFolders.contains(where: { $0.exists && $0.readable == false }) {
            names.append("one or more automation folders")
        }

        return names
    }

    private func plistFiles(
        in directoryURL: URL,
        operation: String,
        scanNotes: inout [AutomationDiagnostics.ScanNote]
    ) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        do {
            return try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter {
                $0.pathExtension == "plist" &&
                ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
        } catch {
            scanNotes.append(
                AutomationDiagnostics.ScanNote(
                    path: directoryURL.path,
                    operation: operation,
                    message: error.localizedDescription
                )
            )
            return []
        }
    }

    private enum LintOutcome {
        case notRequested
        case valid
        case invalid(String)
    }

    private func lintPlist(
        at plistURL: URL,
        commandFailures: inout [AutomationDiagnostics.CommandFailure]
    ) -> LintOutcome {
        let result = commandRunner.run(
            .plutil,
            arguments: ["-lint", plistURL.path],
            timeout: configuration.commandTimeout
        )

        if result.succeeded {
            return .valid
        }

        switch result.failureReason {
        case .nonZeroExit:
            let message = combinedOutput(from: result)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .invalid(message.isEmpty ? "plutil reported invalid syntax." : message)
        case .launchFailed, .timedOut:
            commandFailures.append(commandFailure(from: result))
            return .notRequested
        case nil:
            return .notRequested
        }
    }

    private func loadPlist(
        at plistURL: URL,
        operation: String,
        scanNotes: inout [AutomationDiagnostics.ScanNote]
    ) -> [String: Any]? {
        do {
            let data = try Data(contentsOf: plistURL, options: [.mappedIfSafe])
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return object as? [String: Any]
        } catch {
            scanNotes.append(
                AutomationDiagnostics.ScanNote(
                    path: plistURL.path,
                    operation: operation,
                    message: error.localizedDescription
                )
            )
            return nil
        }
    }

    private func executablePath(from plist: [String: Any]) -> String? {
        if let program = plist["Program"] as? String, !program.isEmpty {
            return program
        }

        if
            let programArguments = plist["ProgramArguments"] as? [String],
            let firstArgument = programArguments.first,
            !firstArgument.isEmpty
        {
            return firstArgument
        }

        return nil
    }

    private func keepAliveValue(from rawValue: Any?) -> Bool {
        if let boolValue = rawValue as? Bool {
            return boolValue
        }

        if let dictionaryValue = rawValue as? [String: Any] {
            return !dictionaryValue.isEmpty
        }

        return false
    }

    private func fileExists(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path) || FileManager.default.fileExists(atPath: path)
    }

    private func parentDirectoryExists(for path: String) -> Bool {
        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: parentPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func homebrewExists() -> Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
    }

    private func parseHomebrewServiceLine(_ line: String) -> AutomationDiagnostics.HomebrewService? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else {
            return nil
        }

        let parts = trimmedLine
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard parts.count >= 2 else {
            return nil
        }

        let name = parts[0]
        // Ensure name only contains characters typical of a Homebrew package/service name
        // (alphanumerics, dashes, underscores, dots, plusses, at-signs) to filter out CLI decorations like ✔︎ or ==>
        let allowedSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_+.@"))
        guard name.unicodeScalars.allSatisfy({ allowedSet.contains($0) }) else {
            return nil
        }

        return AutomationDiagnostics.HomebrewService(
            name: name,
            status: parts[1],
            user: parts.count >= 3 ? parts[2] : nil,
            plistPath: parts.count >= 4 ? parts[3] : nil
        )
    }

    private func homebrewServiceNeedsAttention(_ service: AutomationDiagnostics.HomebrewService) -> Bool {
        switch service.status.lowercased() {
        case "started", "none", "scheduled":
            return false
        default:
            return true
        }
    }

    private func combinedOutput(from result: SafeCommandRunner.ExecutionResult) -> String {
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (stdout.isEmpty, stderr.isEmpty) {
        case (false, false):
            return stdout + "\n" + stderr
        case (false, true):
            return stdout
        case (true, false):
            return stderr
        case (true, true):
            return ""
        }
    }

    private func commandFailure(
        from result: SafeCommandRunner.ExecutionResult
    ) -> AutomationDiagnostics.CommandFailure {
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

        return AutomationDiagnostics.CommandFailure(
            command: result.command.displayName,
            arguments: result.arguments,
            message: message,
            standardError: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private extension Sequence where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
