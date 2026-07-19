import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private enum AnalysisProgress: Sendable {
        case storage(StorageDiagnosticsCollector.CollectionResult)
        case performance(PerformanceDiagnosticsCollector.CollectionResult)
        case security(SecurityDiagnosticsCollector.CollectionResult)
        case automation(AutomationDiagnosticsCollector.CollectionResult)
    }

    private static let openAIKeychainAccount = "openai_api_key"

    var currentReport: HealthReport
    var latestScanTimestamp: Date?
    var latestReportFiles: GeneratedReportFiles?
    var lastStatusMessage = "Ready. No checks have been run yet."
    var isAnalyzing = false
    var isExplainingWithAI = false
    var latestAIExplanation: AIExplanation?
    var isMaintenanceCenterPresented = false
    var isPerformingMaintenanceAction = false
    var availableCacheFolders: [UserCacheFolderSnapshot]
    var aiProvider: AIProvider {
        didSet {
            persistAIConfiguration()
        }
    }
    var localAIBaseURL: String {
        didSet {
            persistAIConfiguration()
        }
    }
    var localAIModelName: String {
        didSet {
            persistAIConfiguration()
        }
    }
    var ollamaBaseURL: String {
        didSet {
            persistAIConfiguration()
        }
    }
    var ollamaModelName: String {
        didSet {
            persistAIConfiguration()
        }
    }
    var aiTimeoutSeconds: Double {
        didSet {
            persistAIConfiguration()
        }
    }
    var openAIModelName: String {
        didSet {
            persistAIConfiguration()
        }
    }
    var openAIAPIKeyDraft = ""
    var isOpenAIAPIKeyStored: Bool
    var discoveredOllamaModels: [OllamaModelSummary]
    var isRefreshingOllamaModels = false
    var ollamaRefreshStatusText = "No live Ollama models loaded yet."

    private let reportStore: ReportStore
    private let systemProfileProvider: SystemProfileProvider
    private let storageDiagnosticsCollector: StorageDiagnosticsCollector
    private let performanceDiagnosticsCollector: PerformanceDiagnosticsCollector
    private let securityDiagnosticsCollector: SecurityDiagnosticsCollector
    private let automationDiagnosticsCollector: AutomationDiagnosticsCollector
    private let preferencesStore: PreferencesStore
    private let keychainStore: any SecretStoring
    private let maintenanceService: MaintenanceService
    private let aiExplanationService: AIExplanationService
    private let ollamaModelDiscoveryService: OllamaModelDiscoveryService

    init(
        reportStore: ReportStore = ReportStore(),
        systemProfileProvider: SystemProfileProvider = SystemProfileProvider(),
        storageDiagnosticsCollector: StorageDiagnosticsCollector = StorageDiagnosticsCollector(),
        performanceDiagnosticsCollector: PerformanceDiagnosticsCollector = PerformanceDiagnosticsCollector(),
        securityDiagnosticsCollector: SecurityDiagnosticsCollector = SecurityDiagnosticsCollector(),
        automationDiagnosticsCollector: AutomationDiagnosticsCollector = AutomationDiagnosticsCollector(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        keychainStore: any SecretStoring = KeychainStore(),
        maintenanceService: MaintenanceService = MaintenanceService(),
        aiExplanationService: AIExplanationService = AIExplanationService(),
        ollamaModelDiscoveryService: OllamaModelDiscoveryService = OllamaModelDiscoveryService()
    ) {
        self.reportStore = reportStore
        self.systemProfileProvider = systemProfileProvider
        self.storageDiagnosticsCollector = storageDiagnosticsCollector
        self.performanceDiagnosticsCollector = performanceDiagnosticsCollector
        self.securityDiagnosticsCollector = securityDiagnosticsCollector
        self.automationDiagnosticsCollector = automationDiagnosticsCollector
        self.preferencesStore = preferencesStore
        self.keychainStore = keychainStore
        self.maintenanceService = maintenanceService
        self.aiExplanationService = aiExplanationService
        self.ollamaModelDiscoveryService = ollamaModelDiscoveryService

        let aiConfiguration = preferencesStore.loadAIConfiguration()
        aiProvider = aiConfiguration.provider
        localAIBaseURL = aiConfiguration.localBaseURL
        localAIModelName = aiConfiguration.localModelName
        ollamaBaseURL = aiConfiguration.ollamaBaseURL
        ollamaModelName = aiConfiguration.ollamaModelName
        aiTimeoutSeconds = aiConfiguration.timeoutSeconds
        openAIModelName = aiConfiguration.openAIModelName
        availableCacheFolders = maintenanceService.availableCacheFolders()
        isOpenAIAPIKeyStored = (try? keychainStore.loadSecret(account: Self.openAIKeychainAccount)) != nil
        discoveredOllamaModels = []

        let machine = systemProfileProvider.snapshot()
        currentReport = HealthReport.placeholder(
            machine: machine,
            lastStatusMessage: "Ready. No checks have been run yet."
        )
    }

    var healthScore: String {
        currentReport.scoreSummary.scoreDisplayText
    }

    var healthScoreDetail: String {
        let scoreSummary = currentReport.scoreSummary
        guard let storageComponent = scoreSummary.components.first(where: { $0.category == .storage }) else {
            return "No category scores are available yet."
        }

        let weightedScore = String(format: "%.1f", storageComponent.weightedScore)

        if scoreSummary.overallStatus == .unknown {
            return "Storage contributes \(weightedScore) weighted points while other categories remain unknown."
        }

        return "Current overall status is \(scoreSummary.overallStatus.displayName)."
    }

    var storageStatus: String {
        currentReport.storage.status.displayName
    }

    var storageStatusDetail: String {
        if isAnalyzing {
            return "Scanning Downloads, Trash, Caches, and visible home files."
        }

        if
            let freeCapacityBytes = currentReport.storage.freeCapacityBytes,
            let freeCapacityPercent = currentReport.storage.freeCapacityPercent
        {
            return "\(StorageFormatters.byteCountString(from: freeCapacityBytes)) free (\(StorageFormatters.percentageString(from: freeCapacityPercent)))."
        }

        return "Run Analyze My Mac to collect real storage metrics."
    }

    var performanceStatus: String {
        currentReport.performance.status.displayName
    }

    var performanceStatusDetail: String {
        if isAnalyzing {
            return "Collecting CPU, memory, uptime, process, and user service data."
        }

        var parts: [String] = []

        if let cpuLoadPercent = currentReport.performance.cpuLoadPercent {
            parts.append("\(PerformanceFormatters.cpuLoadString(from: cpuLoadPercent)) CPU load")
        }

        if let memoryPressureSummary = currentReport.performance.memoryPressureSummary {
            parts.append(memoryPressureSummary)
        }

        if let uptimeSeconds = currentReport.performance.uptimeSeconds {
            parts.append("up \(PerformanceFormatters.durationString(from: uptimeSeconds))")
        }

        if parts.isEmpty {
            return "Run Analyze My Mac to collect real performance metrics."
        }

        return parts.joined(separator: " • ")
    }

    var securityStatus: String {
        currentReport.security.status.displayName
    }

    var securityStatusDetail: String {
        if isAnalyzing {
            return "Collecting Gatekeeper, FileVault, SIP, firewall, XProtect, and update data."
        }

        var parts: [String] = []

        if let gatekeeperEnabled = currentReport.security.gatekeeperEnabled {
            parts.append("Gatekeeper \(gatekeeperEnabled ? "on" : "off")")
        }

        if let fileVaultEnabled = currentReport.security.fileVaultEnabled {
            parts.append("FileVault \(fileVaultEnabled ? "on" : "off")")
        }

        if let sipEnabled = currentReport.security.systemIntegrityProtectionEnabled {
            parts.append("SIP \(sipEnabled ? "on" : "off")")
        }

        if parts.isEmpty {
            return "Run Analyze My Mac to collect real security metrics."
        }

        return parts.joined(separator: " • ")
    }

    var automationStatus: String {
        currentReport.automation.status.displayName
    }

    var automationStatusDetail: String {
        if isAnalyzing && !hasCollectedAutomationData {
            return "Inspecting LaunchAgents, automation folders, and Homebrew services."
        }

        let automation = currentReport.automation
        var parts: [String] = []

        let totalLaunchAgents = automation.userLaunchAgents.count + automation.sharedLaunchAgents.count
        if totalLaunchAgents > 0 {
            parts.append("\(totalLaunchAgents) launch agents")
        }

        if !automation.keepAliveAgentLabels.isEmpty {
            parts.append("\(automation.keepAliveAgentLabels.count) KeepAlive")
        }

        if !automation.homebrewServices.isEmpty {
            parts.append("\(automation.homebrewServices.count) Homebrew services")
        }

        if parts.isEmpty {
            return "Run Analyze My Mac to collect real automation metrics."
        }

        return parts.joined(separator: " • ")
    }

    private var hasCollectedAutomationData: Bool {
        let automation = currentReport.automation
        return
            automation.status != .unknown ||
            !automation.userLaunchAgents.isEmpty ||
            !automation.sharedLaunchAgents.isEmpty ||
            automation.systemLaunchAgentCount != nil ||
            automation.systemKeepAliveCount != nil ||
            !automation.homebrewServices.isEmpty
    }

    var latestScanDisplayText: String {
        TimestampFormatter.displayString(from: latestScanTimestamp)
    }

    var latestReportDisplayText: String {
        latestReportFiles?.markdownURL.lastPathComponent ?? "No report generated yet"
    }

    var reportsDirectoryDisplayText: String {
        (try? reportStore.reportsDirectoryURL().path) ?? "Unavailable"
    }

    var openAIKeyStatusText: String {
        isOpenAIAPIKeyStored ? "Stored in macOS Keychain." : "No OpenAI API key stored."
    }

    var ollamaConfiguredModelStatusText: String {
        let configuredModel = ollamaModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuredModel.isEmpty else {
            return "No Ollama model selected."
        }

        guard !discoveredOllamaModels.isEmpty else {
            return "Configured model: \(configuredModel)"
        }

        if discoveredOllamaModels.contains(where: { $0.name == configuredModel }) {
            return "Configured model is available live."
        }

        return "Configured model is not in the current live Ollama list."
    }

    var latestAIExplanationDisplayText: String {
        latestAIExplanation?.content ?? "No AI explanation generated yet."
    }

    var latestAIExplanationDisclaimer: String {
        latestAIExplanation?.disclaimer ?? "AI explanation is advisory. System facts come from local diagnostics."
    }

    var latestAIExplanationTimestampText: String {
        TimestampFormatter.displayString(from: latestAIExplanation?.generatedAt)
    }

    var maintenanceActionDefinitions: [MaintenanceActionDefinition] {
        [
            MaintenanceActionDefinition(
                kind: .emptyTrash,
                title: "Empty Trash",
                explanation: "This removes items currently sitting in the user Trash only.",
                riskLevel: .review,
                estimatedImpact: "Can recover local disk space immediately.",
                reversibility: "Not reversible after confirmation.",
                warning: "Only the user Trash is touched. Nothing outside ~/.Trash is modified."
            ),
            MaintenanceActionDefinition(
                kind: .clearUserCaches,
                title: "Clear Selected User Cache Folders",
                explanation: "This clears the contents of selected folders inside ~/Library/Caches while leaving the folders themselves in place.",
                riskLevel: .review,
                estimatedImpact: "May recover space and resolve stale temporary-data issues for selected apps.",
                reversibility: "Usually reversible because apps rebuild caches, but temporary data may be lost.",
                warning: "Selected cache contents are deleted after confirmation. Review the selection carefully."
            ),
            MaintenanceActionDefinition(
                kind: .openDownloadsFolder,
                title: "Open Downloads Folder for Review",
                explanation: "This opens Downloads in Finder so you can review large or old files manually.",
                riskLevel: .safe,
                estimatedImpact: "Helps identify cleanup candidates without deleting anything.",
                reversibility: "Fully reversible. It only opens Finder.",
                warning: nil
            ),
            MaintenanceActionDefinition(
                kind: .openLoginItemsSettings,
                title: "Open Login Items Settings",
                explanation: "This opens the native macOS Login Items settings page.",
                riskLevel: .safe,
                estimatedImpact: "Helps review background items and login items without changing them automatically.",
                reversibility: "Fully reversible. It only opens System Settings.",
                warning: nil
            ),
            MaintenanceActionDefinition(
                kind: .flushDNSCache,
                title: "Prepare DNS Cache Flush",
                explanation: "This copies the suggested DNS flush command and opens Terminal, but it does not run sudo automatically.",
                riskLevel: .advanced,
                estimatedImpact: "May help if DNS lookups are stale or inconsistent.",
                reversibility: "No automatic changes are made. You must choose whether to run the command yourself.",
                warning: "This action prepares a privileged command only. Review it in Terminal before running."
            ),
            MaintenanceActionDefinition(
                kind: .reindexSpotlight,
                title: "Prepare Spotlight Reindex",
                explanation: "This copies the suggested Spotlight reindex command and opens Terminal, but it does not run it automatically.",
                riskLevel: .advanced,
                estimatedImpact: "May help if Spotlight search results are incomplete or stale.",
                reversibility: "No automatic changes are made. You must choose whether to run the command yourself.",
                warning: "A full Spotlight reindex can be resource-intensive. Review the command before running."
            ),
            MaintenanceActionDefinition(
                kind: .generateMaintenanceReport,
                title: "Generate Maintenance Report",
                explanation: "This generates the current Markdown and JSON report pair, including the maintenance action log.",
                riskLevel: .safe,
                estimatedImpact: "Creates a local report artifact for review or sharing.",
                reversibility: "Fully reversible. It only writes local report files.",
                warning: nil
            ),
        ]
    }

    func manualCommandPreview(for kind: MaintenanceActionKind) -> String? {
        switch kind {
        case .flushDNSCache:
            maintenanceService.dnsFlushCommand()
        case .reindexSpotlight:
            maintenanceService.spotlightReindexCommand()
        default:
            nil
        }
    }

    var storageRecommendations: [MaintenanceRecommendation] {
        currentReport.scoreSummary.recommendations.filter { $0.relatedCategory == .storage }
    }

    var performanceRecommendations: [MaintenanceRecommendation] {
        currentReport.scoreSummary.recommendations.filter { $0.relatedCategory == .performance }
    }

    var securityRecommendations: [MaintenanceRecommendation] {
        currentReport.scoreSummary.recommendations.filter { $0.relatedCategory == .security }
    }

    var automationRecommendations: [MaintenanceRecommendation] {
        currentReport.scoreSummary.recommendations.filter { $0.relatedCategory == .automation }
    }

    func runQuickCheck() {
        performAnalysis(triggerLabel: "Quick check")
    }

    func analyzeMyMac() {
        performAnalysis(triggerLabel: "Analyze My Mac")
    }

    func generateReport(openAfterCreate: Bool = false) {
        let generatedAt = Date()
        latestScanTimestamp = generatedAt
        currentReport.generatedAt = generatedAt

        do {
            let report = reportSnapshot(generatedAt: generatedAt)
            let files = try reportStore.writeReport(report: report)
            latestReportFiles = files
            lastStatusMessage = timestampedMessage("Report generated", at: generatedAt)
            currentReport.lastStatusMessage = lastStatusMessage

            if openAfterCreate {
                _ = NSWorkspace.shared.open(files.markdownURL)
                NSWorkspace.shared.activateFileViewerSelecting([files.markdownURL, files.jsonURL])
            }
        } catch {
            lastStatusMessage = "Report generation failed: \(error.localizedDescription)"
            currentReport.lastStatusMessage = lastStatusMessage
        }
    }

    @discardableResult
    func openLatestReport() -> Bool {
        let latestFiles = latestReportFiles ?? (try? reportStore.latestReportFiles())
        guard let latestFiles else {
            lastStatusMessage = "No report generated yet."
            currentReport.lastStatusMessage = lastStatusMessage
            return false
        }

        guard
            FileManager.default.fileExists(atPath: latestFiles.markdownURL.path),
            FileManager.default.fileExists(atPath: latestFiles.jsonURL.path)
        else {
            self.latestReportFiles = nil
            lastStatusMessage = "Latest report could not be found."
            currentReport.lastStatusMessage = lastStatusMessage
            return false
        }

        self.latestReportFiles = latestFiles
        let didOpen = NSWorkspace.shared.open(latestFiles.markdownURL)
        NSWorkspace.shared.activateFileViewerSelecting([latestFiles.markdownURL, latestFiles.jsonURL])
        lastStatusMessage = didOpen
            ? timestampedMessage("Opened latest report")
            : "Latest report could not be opened."
        currentReport.lastStatusMessage = lastStatusMessage
        return didOpen
    }

    func explainWithAI() {
        guard !isExplainingWithAI else {
            lastStatusMessage = "An AI explanation is already running."
            currentReport.lastStatusMessage = lastStatusMessage
            return
        }

        guard aiProvider != .disabled else {
            lastStatusMessage = timestampedMessage("AI is disabled in Preferences")
            currentReport.lastStatusMessage = lastStatusMessage
            return
        }

        let generatedAt = Date()
        let report = reportSnapshot(generatedAt: generatedAt)
        let markdown = reportStore.markdownString(for: report)
        let configuration = aiConfiguration
        let aiExplanationService = aiExplanationService
        let keychainStore = keychainStore
        let keyAccount = Self.openAIKeychainAccount

        isExplainingWithAI = true
        lastStatusMessage = "Preparing AI explanation."
        currentReport.lastStatusMessage = lastStatusMessage

        Task.detached(priority: .userInitiated) {
            let openAIAPIKey = try? keychainStore.loadSecret(account: keyAccount)

            do {
                let explanation = try await aiExplanationService.explain(
                    report: report,
                    reportMarkdown: markdown,
                    configuration: configuration,
                    openAIAPIKey: openAIAPIKey ?? nil
                )

                await MainActor.run {
                    self.latestAIExplanation = explanation
                    self.currentReport.aiExplanation = explanation
                    self.isExplainingWithAI = false
                    self.lastStatusMessage = self.timestampedMessage("AI explanation generated", at: explanation.generatedAt)
                    self.currentReport.lastStatusMessage = self.lastStatusMessage
                }
            } catch {
                await MainActor.run {
                    self.isExplainingWithAI = false
                    self.lastStatusMessage = "AI explanation failed: \(error.localizedDescription)"
                    self.currentReport.lastStatusMessage = self.lastStatusMessage
                }
            }
        }
    }

    func refreshOllamaModels() {
        guard !isRefreshingOllamaModels else {
            lastStatusMessage = "Ollama model refresh is already running."
            currentReport.lastStatusMessage = lastStatusMessage
            return
        }

        let baseURL = ollamaBaseURL
        let timeoutSeconds = aiTimeoutSeconds
        let discoveryService = ollamaModelDiscoveryService

        isRefreshingOllamaModels = true
        ollamaRefreshStatusText = "Refreshing live models from \(baseURL)."
        lastStatusMessage = ollamaRefreshStatusText
        currentReport.lastStatusMessage = lastStatusMessage

        Task.detached(priority: .userInitiated) {
            do {
                let models = try await discoveryService.fetchModels(
                    baseURL: baseURL,
                    timeoutSeconds: timeoutSeconds
                )

                await MainActor.run {
                    self.isRefreshingOllamaModels = false
                    self.discoveredOllamaModels = models

                    if self.ollamaModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let firstModel = models.first {
                        self.ollamaModelName = firstModel.name
                    }

                    let message = models.isEmpty
                        ? "No live Ollama models were returned by \(baseURL)."
                        : "Loaded \(models.count) live Ollama model\(self.pluralSuffix(for: models.count)) from Ollama."
                    self.ollamaRefreshStatusText = message
                    self.lastStatusMessage = self.timestampedMessage(message)
                    self.currentReport.lastStatusMessage = self.lastStatusMessage
                }
            } catch {
                await MainActor.run {
                    self.isRefreshingOllamaModels = false
                    self.ollamaRefreshStatusText = error.localizedDescription
                    self.lastStatusMessage = "Ollama model refresh failed: \(error.localizedDescription)"
                    self.currentReport.lastStatusMessage = self.lastStatusMessage
                }
            }
        }
    }

    func useOllamaModel(_ modelName: String) {
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelName.isEmpty else {
            return
        }

        ollamaModelName = trimmedModelName
        lastStatusMessage = timestampedMessage("Selected Ollama model \(trimmedModelName)")
        currentReport.lastStatusMessage = lastStatusMessage
    }

    func runSafeMaintenance() {
        availableCacheFolders = maintenanceService.availableCacheFolders()
        isMaintenanceCenterPresented = true
        lastStatusMessage = "Review the maintenance actions before confirming any change."
        currentReport.lastStatusMessage = lastStatusMessage
    }

    func dismissMaintenanceCenter() {
        isMaintenanceCenterPresented = false
    }

    func saveOpenAIAPIKey() {
        let key = openAIAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastStatusMessage = "OpenAI API key field is empty."
            currentReport.lastStatusMessage = lastStatusMessage
            return
        }

        do {
            try keychainStore.saveSecret(key, account: Self.openAIKeychainAccount)
            openAIAPIKeyDraft = ""
            isOpenAIAPIKeyStored = true
            lastStatusMessage = "OpenAI API key saved to Keychain."
            currentReport.lastStatusMessage = lastStatusMessage
        } catch {
            lastStatusMessage = "OpenAI API key could not be saved: \(error.localizedDescription)"
            currentReport.lastStatusMessage = lastStatusMessage
        }
    }

    func clearOpenAIAPIKey() {
        do {
            try keychainStore.deleteSecret(account: Self.openAIKeychainAccount)
            openAIAPIKeyDraft = ""
            isOpenAIAPIKeyStored = false
            lastStatusMessage = "OpenAI API key removed from Keychain."
            currentReport.lastStatusMessage = lastStatusMessage
        } catch {
            lastStatusMessage = "OpenAI API key could not be removed: \(error.localizedDescription)"
            currentReport.lastStatusMessage = lastStatusMessage
        }
    }

    @discardableResult
    func openReportsFolder() -> Bool {
        do {
            let reportsDirectory = try reportStore.reportsDirectoryURL()
            let didOpen = NSWorkspace.shared.open(reportsDirectory)
            lastStatusMessage = didOpen
                ? timestampedMessage("Opened report folder")
                : "Report folder could not be opened."
            currentReport.lastStatusMessage = lastStatusMessage
            return didOpen
        } catch {
            lastStatusMessage = "Report folder could not be opened: \(error.localizedDescription)"
            currentReport.lastStatusMessage = lastStatusMessage
            return false
        }
    }

    func performMaintenanceAction(
        _ definition: MaintenanceActionDefinition,
        selectedCacheFolders: [UserCacheFolderSnapshot] = []
    ) {
        guard !isPerformingMaintenanceAction else {
            lastStatusMessage = "A maintenance action is already running."
            currentReport.lastStatusMessage = lastStatusMessage
            return
        }

        switch definition.kind {
        case .openDownloadsFolder:
            let didOpen = NSWorkspace.shared.open(maintenanceService.configuration.downloadsDirectoryURL)
            finalizeMaintenanceAction(
                definition,
                result: didOpen ? .opened : .failed,
                details: didOpen
                    ? "Opened Downloads in Finder for manual review."
                    : "Downloads could not be opened in Finder.",
                lastMaintenanceDate: nil
            )
        case .openLoginItemsSettings:
            let deepLink = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            let didOpen = if let deepLink {
                NSWorkspace.shared.open(deepLink)
            } else {
                false
            }
            let openedSystemSettings = didOpen || NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            finalizeMaintenanceAction(
                definition,
                result: openedSystemSettings ? .opened : .failed,
                details: openedSystemSettings
                    ? "Opened Login Items settings for manual review."
                    : "Login Items settings could not be opened.",
                lastMaintenanceDate: nil
            )
        case .flushDNSCache:
            prepareManualMaintenanceCommand(
                definition,
                command: maintenanceService.dnsFlushCommand(),
                successDetails: "Copied the DNS cache flush command to the clipboard and opened Terminal.",
                failureDetails: "The DNS cache flush command was copied, but Terminal could not be opened."
            )
        case .reindexSpotlight:
            prepareManualMaintenanceCommand(
                definition,
                command: maintenanceService.spotlightReindexCommand(),
                successDetails: "Copied the Spotlight reindex command to the clipboard and opened Terminal.",
                failureDetails: "The Spotlight reindex command was copied, but Terminal could not be opened."
            )
        case .generateMaintenanceReport:
            finalizeMaintenanceAction(
                definition,
                result: .completed,
                details: "Generated a maintenance report in the local report folder.",
                lastMaintenanceDate: nil
            )
            generateReport(openAfterCreate: true)
        case .emptyTrash, .clearUserCaches:
            isPerformingMaintenanceAction = true
            let maintenanceService = maintenanceService

            Task.detached(priority: .userInitiated) {
                do {
                    let executionResult: MaintenanceService.ExecutionResult
                    switch definition.kind {
                    case .emptyTrash:
                        executionResult = try maintenanceService.emptyTrash()
                    case .clearUserCaches:
                        executionResult = try maintenanceService.clearCacheFolders(selectedCacheFolders)
                    default:
                        return
                    }

                    await MainActor.run {
                        self.isPerformingMaintenanceAction = false
                        self.availableCacheFolders = maintenanceService.availableCacheFolders()
                        self.finalizeMaintenanceAction(
                            definition,
                            result: executionResult.result,
                            details: executionResult.details,
                            lastMaintenanceDate: executionResult.lastMaintenanceDate
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.isPerformingMaintenanceAction = false
                        self.finalizeMaintenanceAction(
                            definition,
                            result: .failed,
                            details: error.localizedDescription,
                            lastMaintenanceDate: nil
                        )
                    }
                }
            }
        }
    }

    private func performAnalysis(triggerLabel: String) {
        guard !isAnalyzing else {
            lastStatusMessage = "Analysis is already running."
            currentReport.lastStatusMessage = lastStatusMessage
            return
        }

        let runDate = Date()
        let storageCollector = storageDiagnosticsCollector
        let performanceCollector = performanceDiagnosticsCollector
        let securityCollector = securityDiagnosticsCollector
        let automationCollector = automationDiagnosticsCollector

        isAnalyzing = true
        invalidateAIExplanation()
        latestScanTimestamp = runDate
        currentReport.generatedAt = runDate
        currentReport.machine = systemProfileProvider.snapshot()
        lastStatusMessage = "\(triggerLabel) started at \(TimestampFormatter.displayString(from: runDate))."
        currentReport.lastStatusMessage = lastStatusMessage

        Task.detached(priority: .userInitiated) {
            var storageResult: StorageDiagnosticsCollector.CollectionResult?
            var performanceResult: PerformanceDiagnosticsCollector.CollectionResult?
            var securityResult: SecurityDiagnosticsCollector.CollectionResult?
            var automationResult: AutomationDiagnosticsCollector.CollectionResult?

            await withTaskGroup(of: AnalysisProgress.self) { group in
                group.addTask {
                    .storage(storageCollector.collect(now: runDate))
                }
                group.addTask {
                    .performance(performanceCollector.collect(now: runDate))
                }
                group.addTask {
                    .security(securityCollector.collect())
                }
                group.addTask {
                    .automation(automationCollector.collect())
                }

                for await progress in group {
                    switch progress {
                    case .storage(let result):
                        storageResult = result
                    case .performance(let result):
                        performanceResult = result
                    case .security(let result):
                        securityResult = result
                    case .automation(let result):
                        automationResult = result
                    }

                    let storageSnapshot = storageResult
                    let performanceSnapshot = performanceResult
                    let securitySnapshot = securityResult
                    let automationSnapshot = automationResult

                    await MainActor.run {
                        self.currentReport.generatedAt = runDate
                        self.currentReport.machine = self.systemProfileProvider.snapshot()
                        self.latestScanTimestamp = runDate

                        if let storageSnapshot {
                            self.currentReport.storage = storageSnapshot.diagnostics
                        }

                        if let performanceSnapshot {
                            self.currentReport.performance = performanceSnapshot.diagnostics
                        }

                        if let securitySnapshot {
                            self.currentReport.security = securitySnapshot.diagnostics
                        }

                        if let automationSnapshot {
                            self.currentReport.automation = automationSnapshot.diagnostics
                        }

                        self.currentReport.recommendations = self.mergedRecommendations(
                            storageSnapshot?.recommendations ?? [],
                            performanceSnapshot?.recommendations ?? [],
                            securitySnapshot?.recommendations ?? [],
                            automationSnapshot?.recommendations ?? []
                        )
                        self.currentReport.lastStatusMessage = self.lastStatusMessage
                    }
                }
            }

            guard
                let storageResult,
                let performanceResult,
                let securityResult,
                let automationResult
            else {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.lastStatusMessage = "\(triggerLabel) ended before all diagnostics finished."
                    self.currentReport.lastStatusMessage = self.lastStatusMessage
                }
                return
            }

            await MainActor.run {
                self.currentReport.generatedAt = runDate
                self.currentReport.storage = storageResult.diagnostics
                self.currentReport.performance = performanceResult.diagnostics
                self.currentReport.security = securityResult.diagnostics
                self.currentReport.automation = automationResult.diagnostics
                self.currentReport.recommendations = self.mergedRecommendations(
                    storageResult.recommendations,
                    performanceResult.recommendations,
                    securityResult.recommendations,
                    automationResult.recommendations
                )
                self.currentReport.machine = self.systemProfileProvider.snapshot()
                self.latestScanTimestamp = runDate
                self.isAnalyzing = false

                let issueCount =
                    storageResult.diagnostics.issues.count +
                    performanceResult.diagnostics.issues.count +
                    securityResult.diagnostics.issues.count +
                    automationResult.diagnostics.issues.count
                let recommendationCount = self.currentReport.recommendations.count

                self.lastStatusMessage = self.timestampedMessage(
                    "\(triggerLabel) completed with storage \(storageResult.diagnostics.status.displayName.lowercased()), performance \(performanceResult.diagnostics.status.displayName.lowercased()), security \(securityResult.diagnostics.status.displayName.lowercased()), automation \(automationResult.diagnostics.status.displayName.lowercased()), \(issueCount) issue\(self.pluralSuffix(for: issueCount)), \(recommendationCount) recommendation\(self.pluralSuffix(for: recommendationCount))",
                    at: runDate
                )
                self.currentReport.lastStatusMessage = self.lastStatusMessage
            }
        }
    }

    private func reportSnapshot(generatedAt: Date) -> HealthReport {
        var report = currentReport
        report.generatedAt = generatedAt
        report.machine = systemProfileProvider.snapshot()
        report.aiExplanation = latestAIExplanation
        report.lastStatusMessage = lastStatusMessage
        return report
    }

    private var aiConfiguration: AIConfiguration {
        AIConfiguration(
            provider: aiProvider,
            localBaseURL: localAIBaseURL,
            localModelName: localAIModelName,
            ollamaBaseURL: ollamaBaseURL,
            ollamaModelName: ollamaModelName,
            timeoutSeconds: aiTimeoutSeconds,
            openAIModelName: openAIModelName
        )
    }

    private func persistAIConfiguration() {
        preferencesStore.saveAIConfiguration(aiConfiguration)
    }

    private func prepareManualMaintenanceCommand(
        _ definition: MaintenanceActionDefinition,
        command: String,
        successDetails: String,
        failureDetails: String
    ) {
        copyToPasteboard(command)
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let didOpenTerminal = NSWorkspace.shared.open(terminalURL)

        finalizeMaintenanceAction(
            definition,
            result: didOpenTerminal ? .manualActionRequired : .failed,
            details: didOpenTerminal ? successDetails : failureDetails,
            lastMaintenanceDate: nil
        )
    }

    private func finalizeMaintenanceAction(
        _ definition: MaintenanceActionDefinition,
        result: MaintenanceActionRecord.Result,
        details: String,
        lastMaintenanceDate: Date?
    ) {
        invalidateAIExplanation()

        if let lastMaintenanceDate {
            currentReport.lastMaintenanceDate = lastMaintenanceDate
        }

        let record = MaintenanceActionRecord(
            kind: definition.kind,
            title: definition.title,
            explanation: definition.explanation,
            riskLevel: definition.riskLevel,
            estimatedImpact: definition.estimatedImpact,
            reversibility: definition.reversibility,
            result: result,
            details: details
        )
        currentReport.maintenanceActions.insert(record, at: 0)

        lastStatusMessage = timestampedMessage(details)
        currentReport.lastStatusMessage = lastStatusMessage
    }

    private func invalidateAIExplanation() {
        latestAIExplanation = nil
        currentReport.aiExplanation = nil
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func timestampedMessage(_ message: String, at date: Date = Date()) -> String {
        "\(message) at \(TimestampFormatter.displayString(from: date))."
    }

    private func pluralSuffix(for count: Int) -> String {
        count == 1 ? "" : "s"
    }

    private func mergedRecommendations(
        _ groups: [MaintenanceRecommendation]...
    ) -> [MaintenanceRecommendation] {
        var seenKeys: Set<String> = []
        var merged: [MaintenanceRecommendation] = []

        for recommendation in groups.joined() {
            let key = "\(recommendation.relatedCategory.rawValue):\(recommendation.title)"
            if seenKeys.insert(key).inserted {
                merged.append(recommendation)
            }
        }

        return merged
    }
}
