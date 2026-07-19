import Foundation

enum DiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case storage
    case performance
    case security
    case automation
    case maintenance

    var displayName: String {
        switch self {
        case .storage:
            "Storage"
        case .performance:
            "Performance"
        case .security:
            "Security"
        case .automation:
            "Automation"
        case .maintenance:
            "Maintenance"
        }
    }

    var weightPercentage: Double {
        switch self {
        case .storage:
            25
        case .performance:
            25
        case .security:
            25
        case .automation:
            15
        case .maintenance:
            10
        }
    }
}
