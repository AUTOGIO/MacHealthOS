import Foundation

struct HealthReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var machine: MachineProfile
    var storage: StorageDiagnostics
    var performance: PerformanceDiagnostics
    var security: SecurityDiagnostics
    var automation: AutomationDiagnostics
    var lastMaintenanceDate: Date?
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
        self.lastMaintenanceDate = lastMaintenanceDate
        self.recommendations = recommendations
        self.maintenanceActions = maintenanceActions
        self.aiExplanation = aiExplanation
        self.lastStatusMessage = lastStatusMessage
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
}
