import Foundation
import Testing
@testable import MacHealthOS

@Test func maintenanceStateStoreMissingFileReturnsEmpty() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacHealthOS-MaintenanceState-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = MaintenanceStateStore(
        configuration: .init(homeDirectoryURL: root)
    )
    let state = store.load()

    #expect(state.lastReadOnlyHealthScanAt == nil)
    #expect(state.lastApprovedMaintenanceAt == nil)
    #expect(state.lastMaintenanceSummary == MaintenanceState.defaultSummary)
    #expect(state.hasNoFreshnessHistory)
}

@Test func maintenanceStateStoreRecordsScanAndApprovedMaintenanceAtomically() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacHealthOS-MaintenanceState-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = MaintenanceStateStore(
        configuration: .init(homeDirectoryURL: root)
    )
    let scanAt = Date(timeIntervalSince1970: 1_700_000_100)
    let maintenanceAt = Date(timeIntervalSince1970: 1_700_000_200)

    let afterScan = try store.recordSuccessfulReadOnlyScan(at: scanAt)
    #expect(afterScan.lastReadOnlyHealthScanAt == scanAt)
    #expect(afterScan.lastApprovedMaintenanceAt == nil)
    #expect(afterScan.lastMaintenanceSummary == MaintenanceState.defaultSummary)

    let afterMaintenance = try store.recordApprovedMaintenance(
        summary: "Empty Trash: Removed 2 items.",
        at: maintenanceAt
    )
    #expect(afterMaintenance.lastReadOnlyHealthScanAt == scanAt)
    #expect(afterMaintenance.lastApprovedMaintenanceAt == maintenanceAt)
    #expect(afterMaintenance.lastMaintenanceSummary == "Empty Trash: Removed 2 items.")

    let reloaded = store.load()
    #expect(reloaded == afterMaintenance)
    #expect(FileManager.default.fileExists(atPath: storeConfigurationStatePath(root)))
}

@Test func maintenanceStateStoreMalformedJSONFallsBackToEmpty() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacHealthOS-MaintenanceState-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let stateDirectory = root
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("MacHealthOS", isDirectory: true)
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    let stateURL = stateDirectory.appendingPathComponent("maintenance-state.json")
    try Data("{not-json".utf8).write(to: stateURL)

    let store = MaintenanceStateStore(configuration: .init(homeDirectoryURL: root))
    let state = store.load()
    #expect(state == .empty)
}

@Test func healthReportDecodesLegacyPayloadWithoutMaintenanceStateFields() async throws {
    let original = HealthReport(
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        machine: MachineProfile(
            machineName: "Test",
            macOSVersion: "Version 27.0",
            hardwareArchitecture: "arm64"
        ),
        storage: StorageDiagnostics(status: .healthy),
        performance: PerformanceDiagnostics(status: .healthy),
        security: SecurityDiagnostics(status: .healthy),
        automation: AutomationDiagnostics(status: .healthy),
        lastReadOnlyHealthScanAt: Date(timeIntervalSince1970: 1_700_000_050),
        lastApprovedMaintenanceAt: Date(timeIntervalSince1970: 1_700_000_060),
        lastMaintenanceSummary: "Empty Trash: Removed 1 item.",
        lastStatusMessage: "Ready."
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var object = try JSONSerialization.jsonObject(with: encoder.encode(original)) as! [String: Any]
    object.removeValue(forKey: "lastReadOnlyHealthScanAt")
    object.removeValue(forKey: "lastApprovedMaintenanceAt")
    object.removeValue(forKey: "lastMaintenanceSummary")
    object.removeValue(forKey: "lastMaintenanceDate")

    let stripped = try JSONSerialization.data(withJSONObject: object)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let report = try decoder.decode(HealthReport.self, from: stripped)

    #expect(report.lastReadOnlyHealthScanAt == nil)
    #expect(report.lastApprovedMaintenanceAt == nil)
    #expect(report.lastMaintenanceSummary == MaintenanceState.defaultSummary)
}

private func storeConfigurationStatePath(_ home: URL) -> String {
    home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("MacHealthOS", isDirectory: true)
        .appendingPathComponent("maintenance-state.json")
        .path
}
