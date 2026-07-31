import Foundation

struct MaintenanceStateStore {
    struct Configuration: Equatable, Sendable {
        var homeDirectoryURL: URL

        init(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
            self.homeDirectoryURL = homeDirectoryURL
        }

        var stateDirectoryURL: URL {
            homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("MacHealthOS", isDirectory: true)
        }

        var stateFileURL: URL {
            stateDirectoryURL.appendingPathComponent("maintenance-state.json")
        }
    }

    private let fileManager = FileManager.default
    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func load() -> MaintenanceState {
        let url = configuration.stateFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var state = try decoder.decode(MaintenanceState.self, from: data)
            if state.schemaVersion < 1 {
                state.schemaVersion = MaintenanceState.currentSchemaVersion
            }
            if state.lastMaintenanceSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.lastMaintenanceSummary = MaintenanceState.defaultSummary
            }
            return state
        } catch {
            return .empty
        }
    }

    func save(_ state: MaintenanceState) throws {
        var normalized = state
        normalized.schemaVersion = MaintenanceState.currentSchemaVersion
        if normalized.lastMaintenanceSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.lastMaintenanceSummary = MaintenanceState.defaultSummary
        }

        let directory = configuration.stateDirectoryURL
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(normalized)

        let destination = configuration.stateFileURL
        let temporaryURL = directory
            .appendingPathComponent("maintenance-state.\(UUID().uuidString).tmp")

        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    @discardableResult
    func recordSuccessfulReadOnlyScan(at date: Date = Date()) throws -> MaintenanceState {
        var state = load()
        state.lastReadOnlyHealthScanAt = date
        try save(state)
        return state
    }

    @discardableResult
    func recordApprovedMaintenance(
        summary: String,
        at date: Date = Date()
    ) throws -> MaintenanceState {
        var state = load()
        state.lastApprovedMaintenanceAt = date
        state.lastMaintenanceSummary = summary
        try save(state)
        return state
    }
}
