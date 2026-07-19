import Foundation

struct MaintenanceActionDefinition: Equatable, Sendable, Identifiable {
    let kind: MaintenanceActionKind
    let title: String
    let explanation: String
    let riskLevel: RiskLevel
    let estimatedImpact: String
    let reversibility: String
    let warning: String?

    var id: MaintenanceActionKind {
        kind
    }
}

struct UserCacheFolderSnapshot: Codable, Equatable, Sendable, Identifiable, Hashable {
    let path: String
    let name: String
    let estimatedSizeBytes: Int64?

    var id: String {
        path
    }
}
