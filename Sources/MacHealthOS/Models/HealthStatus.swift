import Foundation

enum HealthStatus: String, Codable, CaseIterable, Sendable {
    case healthy
    case warning
    case critical
    case unknown

    var displayName: String {
        switch self {
        case .healthy:
            "Healthy"
        case .warning:
            "Warning"
        case .critical:
            "Critical"
        case .unknown:
            "Unknown"
        }
    }

    var baseScore: Int {
        switch self {
        case .healthy:
            100
        case .warning:
            65
        case .critical:
            20
        case .unknown:
            40
        }
    }

    var severityRank: Int {
        switch self {
        case .critical:
            3
        case .warning:
            2
        case .unknown:
            1
        case .healthy:
            0
        }
    }
}
