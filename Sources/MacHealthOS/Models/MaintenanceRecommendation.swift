import Foundation

struct MaintenanceRecommendation: Codable, Equatable, Sendable {
    let title: String
    let explanation: String
    let riskLevel: RiskLevel
    let estimatedImpact: String
    let reversibility: String
    let relatedCategory: DiagnosticCategory
}
