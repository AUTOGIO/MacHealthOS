import Foundation

enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case safe
    case review
    case advanced
    case notRecommended

    var severityRank: Int {
        switch self {
        case .notRecommended:
            3
        case .advanced:
            2
        case .review:
            1
        case .safe:
            0
        }
    }
}
