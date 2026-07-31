import Foundation

struct HealthReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var machine: MachineProfile
    var storage: StorageDiagnostics
    var performance: PerformanceDiagnostics
    var security: SecurityDiagnostics
    var automation: AutomationDiagnostics
    /// Legacy field kept for backward compatibility; mirrors approved maintenance only.
    var lastMaintenanceDate: Date?
    var lastReadOnlyHealthScanAt: Date?
    var lastApprovedMaintenanceAt: Date?
    var lastMaintenanceSummary: String
    var recommendations: [MaintenanceRecommendation]
    var maintenanceActions: [MaintenanceActionRecord]
    var aiExplanation: AIExplanation?
    var lastStatusMessage: String

    init(
        generatedAt: Date = Date(),
        machine: MachineProfile = .unknown,
        storage: StorageDiagnostics = StorageDiagnostics(),
        performance: PerformanceDiagnostics = PerformanceDiagnostics(),
        security: SecurityDiagnostics = SecurityDiagnostics(),
        automation: AutomationDiagnostics = AutomationDiagnostics(),
        lastMaintenanceDate: Date? = nil,
        lastReadOnlyHealthScanAt: Date? = nil,
        lastApprovedMaintenanceAt: Date? = nil,
        lastMaintenanceSummary: String = MaintenanceState.defaultSummary,
        recommendations: [MaintenanceRecommendation] = [],
        maintenanceActions: [MaintenanceActionRecord] = [],
        aiExplanation: AIExplanation? = nil,
        lastStatusMessage: String = "Ready. No checks have been run yet."
    ) {
        self.generatedAt = generatedAt
        self.machine = machine
        self.storage = storage
        self.performance = performance
        self.security = security
        self.automation = automation
        let approved = lastApprovedMaintenanceAt ?? lastMaintenanceDate
        self.lastApprovedMaintenanceAt = approved
        self.lastMaintenanceDate = approved
        self.lastReadOnlyHealthScanAt = lastReadOnlyHealthScanAt
        self.lastMaintenanceSummary = lastMaintenanceSummary
        self.recommendations = recommendations
        self.maintenanceActions = maintenanceActions
        self.aiExplanation = aiExplanation
        self.lastStatusMessage = lastStatusMessage
    }

    mutating func applyMaintenanceState(_ state: MaintenanceState) {
        lastReadOnlyHealthScanAt = state.lastReadOnlyHealthScanAt
        lastApprovedMaintenanceAt = state.lastApprovedMaintenanceAt
        lastMaintenanceDate = state.lastApprovedMaintenanceAt
        lastMaintenanceSummary = state.lastMaintenanceSummary
    }

    static func placeholder(
        generatedAt: Date = Date(),
        machine: MachineProfile = .unknown,
        lastStatusMessage: String = "Ready. No checks have been run yet."
    ) -> HealthReport {
        HealthReport(
            generatedAt: generatedAt,
            machine: machine,
            lastStatusMessage: lastStatusMessage
        )
    }

    var scoreSummary: HealthScoreEngine.Evaluation {
        HealthScoreEngine.default.evaluate(self)
    }

    var topIssues: [HealthIssue] {
        scoreSummary.topIssues
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case machine
        case storage
        case performance
        case security
        case automation
        case lastMaintenanceDate
        case lastReadOnlyHealthScanAt
        case lastApprovedMaintenanceAt
        case lastMaintenanceSummary
        case recommendations
        case maintenanceActions
        case aiExplanation
        case lastStatusMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        machine = try container.decode(MachineProfile.self, forKey: .machine)
        storage = try container.decode(StorageDiagnostics.self, forKey: .storage)
        performance = try container.decode(PerformanceDiagnostics.self, forKey: .performance)
        security = try container.decode(SecurityDiagnostics.self, forKey: .security)
        automation = try container.decode(AutomationDiagnostics.self, forKey: .automation)
        let legacyMaintenance = try container.decodeIfPresent(Date.self, forKey: .lastMaintenanceDate)
        let approved = try container.decodeIfPresent(Date.self, forKey: .lastApprovedMaintenanceAt) ?? legacyMaintenance
        lastApprovedMaintenanceAt = approved
        lastMaintenanceDate = approved
        lastReadOnlyHealthScanAt = try container.decodeIfPresent(Date.self, forKey: .lastReadOnlyHealthScanAt)
        lastMaintenanceSummary = try container.decodeIfPresent(String.self, forKey: .lastMaintenanceSummary)
            ?? MaintenanceState.defaultSummary
        recommendations = try container.decodeIfPresent([MaintenanceRecommendation].self, forKey: .recommendations) ?? []
        maintenanceActions = try container.decodeIfPresent([MaintenanceActionRecord].self, forKey: .maintenanceActions) ?? []
        aiExplanation = try container.decodeIfPresent(AIExplanation.self, forKey: .aiExplanation)
        lastStatusMessage = try container.decodeIfPresent(String.self, forKey: .lastStatusMessage)
            ?? "Ready. No checks have been run yet."
    }
}
