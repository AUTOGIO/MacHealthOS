import Foundation

struct DashboardSnapshot {
    let healthScore: String
    let storageStatus: String
    let performanceStatus: String
    let securityStatus: String
    let automationStatus: String
    let latestScanTimestamp: Date?
    let lastStatusMessage: String
}
