import Foundation

/// Persisted monitoring and approved-maintenance freshness for MacHealthOS.
///
/// A successful read-only scan updates `lastReadOnlyHealthScanAt` only.
/// Approved remediation that actually succeeds updates `lastApprovedMaintenanceAt`
/// and `lastMaintenanceSummary`. Scans are never classified as maintenance.
struct MaintenanceState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let defaultSummary = "No approved maintenance actions recorded."

    var schemaVersion: Int
    var lastReadOnlyHealthScanAt: Date?
    var lastApprovedMaintenanceAt: Date?
    var lastMaintenanceSummary: String

    init(
        schemaVersion: Int = MaintenanceState.currentSchemaVersion,
        lastReadOnlyHealthScanAt: Date? = nil,
        lastApprovedMaintenanceAt: Date? = nil,
        lastMaintenanceSummary: String = MaintenanceState.defaultSummary
    ) {
        self.schemaVersion = schemaVersion
        self.lastReadOnlyHealthScanAt = lastReadOnlyHealthScanAt
        self.lastApprovedMaintenanceAt = lastApprovedMaintenanceAt
        self.lastMaintenanceSummary = lastMaintenanceSummary
    }

    static let empty = MaintenanceState()

    /// Backward-compatible alias used by existing score/report fields.
    var lastMaintenanceDate: Date? {
        lastApprovedMaintenanceAt
    }

    /// True when neither a completed scan nor approved maintenance has been recorded.
    var hasNoFreshnessHistory: Bool {
        lastReadOnlyHealthScanAt == nil && lastApprovedMaintenanceAt == nil
    }
}
