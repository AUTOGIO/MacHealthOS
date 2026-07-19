import Foundation

struct SecurityDiagnostics: Codable, Equatable, Sendable {
    struct PackageReceipt: Codable, Equatable, Sendable {
        let packageIdentifier: String
        let version: String
        let installDate: Date?
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
    var gatekeeperEnabled: Bool?
    var fileVaultEnabled: Bool?
    var systemIntegrityProtectionEnabled: Bool?
    var firewallEnabled: Bool?
    var macOSVersion: String?
    var xProtectPayload: PackageReceipt?
    var xProtectConfigData: PackageReceipt?
    var pendingSecurityUpdatesCount: Int?
    var availableSecurityUpdateLabels: [String]
    var commandFailures: [CommandFailure]
    var issues: [HealthIssue]

    init(
        status: HealthStatus = .unknown,
        gatekeeperEnabled: Bool? = nil,
        fileVaultEnabled: Bool? = nil,
        systemIntegrityProtectionEnabled: Bool? = nil,
        firewallEnabled: Bool? = nil,
        macOSVersion: String? = nil,
        xProtectPayload: PackageReceipt? = nil,
        xProtectConfigData: PackageReceipt? = nil,
        pendingSecurityUpdatesCount: Int? = nil,
        availableSecurityUpdateLabels: [String] = [],
        commandFailures: [CommandFailure] = [],
        issues: [HealthIssue] = []
    ) {
        self.status = status
        self.gatekeeperEnabled = gatekeeperEnabled
        self.fileVaultEnabled = fileVaultEnabled
        self.systemIntegrityProtectionEnabled = systemIntegrityProtectionEnabled
        self.firewallEnabled = firewallEnabled
        self.macOSVersion = macOSVersion
        self.xProtectPayload = xProtectPayload
        self.xProtectConfigData = xProtectConfigData
        self.pendingSecurityUpdatesCount = pendingSecurityUpdatesCount
        self.availableSecurityUpdateLabels = availableSecurityUpdateLabels
        self.commandFailures = commandFailures
        self.issues = issues
    }
}
