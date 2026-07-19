import Foundation

struct AutomationDiagnostics: Codable, Equatable, Sendable {
    enum LaunchAgentDomain: String, Codable, Sendable {
        case user
        case shared
    }

    struct LaunchAgentRecord: Codable, Equatable, Sendable, Identifiable {
        let path: String
        let label: String
        let domain: LaunchAgentDomain
        let lintValid: Bool?
        let keepAlive: Bool
        let runAtLoad: Bool?
        let executablePath: String?
        let executableExists: Bool?
        let standardOutPath: String?
        let standardOutParentExists: Bool?
        let standardErrorPath: String?
        let standardErrorParentExists: Bool?
        let findings: [String]

        var id: String {
            path
        }
    }

    struct FolderSnapshot: Codable, Equatable, Sendable, Identifiable {
        let title: String
        let path: String
        let exists: Bool
        let readable: Bool?
        let itemCount: Int?
        let sampleItems: [String]

        var id: String {
            path
        }
    }

    struct HomebrewService: Codable, Equatable, Sendable, Identifiable {
        let name: String
        let status: String
        let user: String?
        let plistPath: String?

        var id: String {
            name
        }
    }

    struct ScanNote: Codable, Equatable, Sendable, Identifiable {
        let path: String
        let operation: String
        let message: String

        var id: String {
            "\(operation):\(path)"
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
    var userLaunchAgents: [LaunchAgentRecord]
    var sharedLaunchAgents: [LaunchAgentRecord]
    var systemLaunchAgentCount: Int?
    var systemKeepAliveCount: Int?
    var systemSampleLabels: [String]
    var commonFolders: [FolderSnapshot]
    var homebrewServices: [HomebrewService]
    var brokenPlistLabels: [String]
    var missingExecutableLabels: [String]
    var staleLogPathLabels: [String]
    var keepAliveAgentLabels: [String]
    var commandFailures: [CommandFailure]
    var scanNotes: [ScanNote]
    var issues: [HealthIssue]

    init(
        status: HealthStatus = .unknown,
        userLaunchAgents: [LaunchAgentRecord] = [],
        sharedLaunchAgents: [LaunchAgentRecord] = [],
        systemLaunchAgentCount: Int? = nil,
        systemKeepAliveCount: Int? = nil,
        systemSampleLabels: [String] = [],
        commonFolders: [FolderSnapshot] = [],
        homebrewServices: [HomebrewService] = [],
        brokenPlistLabels: [String] = [],
        missingExecutableLabels: [String] = [],
        staleLogPathLabels: [String] = [],
        keepAliveAgentLabels: [String] = [],
        commandFailures: [CommandFailure] = [],
        scanNotes: [ScanNote] = [],
        issues: [HealthIssue] = []
    ) {
        self.status = status
        self.userLaunchAgents = userLaunchAgents
        self.sharedLaunchAgents = sharedLaunchAgents
        self.systemLaunchAgentCount = systemLaunchAgentCount
        self.systemKeepAliveCount = systemKeepAliveCount
        self.systemSampleLabels = systemSampleLabels
        self.commonFolders = commonFolders
        self.homebrewServices = homebrewServices
        self.brokenPlistLabels = brokenPlistLabels
        self.missingExecutableLabels = missingExecutableLabels
        self.staleLogPathLabels = staleLogPathLabels
        self.keepAliveAgentLabels = keepAliveAgentLabels
        self.commandFailures = commandFailures
        self.scanNotes = scanNotes
        self.issues = issues
    }
}
