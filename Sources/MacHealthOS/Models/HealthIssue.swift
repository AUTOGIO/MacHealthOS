import Foundation

struct HealthIssue: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let category: DiagnosticCategory
    let status: HealthStatus
    let title: String
    let explanation: String

    init(
        id: String? = nil,
        category: DiagnosticCategory,
        status: HealthStatus,
        title: String,
        explanation: String
    ) {
        self.id = id ?? "\(category.rawValue):\(title)"
        self.category = category
        self.status = status
        self.title = title
        self.explanation = explanation
    }
}
