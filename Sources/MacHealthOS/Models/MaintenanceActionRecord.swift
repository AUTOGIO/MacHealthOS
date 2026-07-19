import Foundation

enum MaintenanceActionKind: String, Codable, CaseIterable, Sendable {
    case emptyTrash
    case clearUserCaches
    case openDownloadsFolder
    case openLoginItemsSettings
    case flushDNSCache
    case reindexSpotlight
    case generateMaintenanceReport

    var displayName: String {
        switch self {
        case .emptyTrash:
            "Empty Trash"
        case .clearUserCaches:
            "Clear Selected Caches"
        case .openDownloadsFolder:
            "Open Downloads Folder"
        case .openLoginItemsSettings:
            "Open Login Items Settings"
        case .flushDNSCache:
            "Run DNS Cache Flush"
        case .reindexSpotlight:
            "Trigger Spotlight Reindex"
        case .generateMaintenanceReport:
            "Generate Maintenance Report"
        }
    }
}

struct MaintenanceActionRecord: Codable, Equatable, Sendable, Identifiable {
    enum Result: String, Codable, CaseIterable, Sendable {
        case completed
        case failed
        case cancelled
        case manualActionRequired
        case opened

        var displayName: String {
            switch self {
            case .completed:
                "Completed"
            case .failed:
                "Failed"
            case .cancelled:
                "Cancelled"
            case .manualActionRequired:
                "Manual Action Required"
            case .opened:
                "Opened"
            }
        }
    }

    let id: UUID
    let kind: MaintenanceActionKind
    let timestamp: Date
    let title: String
    let explanation: String
    let riskLevel: RiskLevel
    let estimatedImpact: String
    let reversibility: String
    let result: Result
    let details: String

    init(
        id: UUID = UUID(),
        kind: MaintenanceActionKind,
        timestamp: Date = Date(),
        title: String,
        explanation: String,
        riskLevel: RiskLevel,
        estimatedImpact: String,
        reversibility: String,
        result: Result,
        details: String
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.title = title
        self.explanation = explanation
        self.riskLevel = riskLevel
        self.estimatedImpact = estimatedImpact
        self.reversibility = reversibility
        self.result = result
        self.details = details
    }
}
