import Foundation

struct PerformanceDiagnostics: Codable, Equatable, Sendable {
    struct ProcessSnapshot: Codable, Equatable, Sendable, Identifiable {
        let pid: Int
        let command: String
        let cpuPercent: Double?
        let memoryPercent: Double?
        let residentMemoryBytes: Int64?

        var id: Int {
            pid
        }
    }

    struct CommandFailure: Codable, Equatable, Sendable, Identifiable {
        let command: String
        let arguments: [String]
        let message: String
        let standardError: String

        var id: String {
            ([command] + arguments).joined(separator: " ")
        }
    }

    var status: HealthStatus
    var cpuLoadPercent: Double?
    var memoryPressureSummary: String?
    var physicalMemoryBytes: Int64?
    var usedMemoryBytes: Int64?
    var availableMemoryBytes: Int64?
    var uptimeSeconds: TimeInterval?
    var topCPUProcesses: [ProcessSnapshot]
    var topMemoryProcesses: [ProcessSnapshot]
    var accessibleLoginItemLabels: [String]
    var enabledUserServiceLabels: [String]
    var backgroundServiceCount: Int?
    var activeBackgroundServiceCount: Int?
    var commandFailures: [CommandFailure]
    var issues: [HealthIssue]

    init(
        status: HealthStatus = .unknown,
        cpuLoadPercent: Double? = nil,
        memoryPressureSummary: String? = nil,
        physicalMemoryBytes: Int64? = nil,
        usedMemoryBytes: Int64? = nil,
        availableMemoryBytes: Int64? = nil,
        uptimeSeconds: TimeInterval? = nil,
        topCPUProcesses: [ProcessSnapshot] = [],
        topMemoryProcesses: [ProcessSnapshot] = [],
        accessibleLoginItemLabels: [String] = [],
        enabledUserServiceLabels: [String] = [],
        backgroundServiceCount: Int? = nil,
        activeBackgroundServiceCount: Int? = nil,
        commandFailures: [CommandFailure] = [],
        issues: [HealthIssue] = []
    ) {
        self.status = status
        self.cpuLoadPercent = cpuLoadPercent
        self.memoryPressureSummary = memoryPressureSummary
        self.physicalMemoryBytes = physicalMemoryBytes
        self.usedMemoryBytes = usedMemoryBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.uptimeSeconds = uptimeSeconds
        self.topCPUProcesses = topCPUProcesses
        self.topMemoryProcesses = topMemoryProcesses
        self.accessibleLoginItemLabels = accessibleLoginItemLabels
        self.enabledUserServiceLabels = enabledUserServiceLabels
        self.backgroundServiceCount = backgroundServiceCount
        self.activeBackgroundServiceCount = activeBackgroundServiceCount
        self.commandFailures = commandFailures
        self.issues = issues
    }
}
