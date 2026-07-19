import Foundation
import Testing
@testable import MacHealthOS

@Test func automationCollectorBuildsFindingsFromLocalMetadata() async throws {
    let fixture = try AutomationFixture()
    defer { fixture.cleanup() }

    try fixture.writeLaunchAgent(
        named: "com.example.keepalive.one",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.keepalive.one",
            "Program": "/usr/bin/true",
            "KeepAlive": true,
        ]
    )
    try fixture.writeLaunchAgent(
        named: "com.example.keepalive.two",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.keepalive.two",
            "Program": "/usr/bin/true",
            "KeepAlive": true,
        ]
    )
    try fixture.writeLaunchAgent(
        named: "com.example.keepalive.three",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.keepalive.three",
            "Program": "/usr/bin/true",
            "KeepAlive": true,
        ]
    )
    try fixture.writeLaunchAgent(
        named: "com.example.keepalive.four",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.keepalive.four",
            "Program": "/usr/bin/true",
            "KeepAlive": true,
        ]
    )
    try fixture.writeLaunchAgent(
        named: "com.example.keepalive.five",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.keepalive.five",
            "Program": "/usr/bin/true",
            "KeepAlive": true,
        ]
    )
    try fixture.writeLaunchAgent(
        named: "com.example.missing",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.missing",
            "Program": "/tmp/does-not-exist",
        ]
    )
    try fixture.writeLaunchAgent(
        named: "com.example.logs",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.logs",
            "Program": "/usr/bin/true",
            "StandardOutPath": fixture.rootURL.appendingPathComponent("missing/logs/stdout.log").path,
            "StandardErrorPath": fixture.rootURL.appendingPathComponent("missing/logs/stderr.log").path,
        ]
    )
    try fixture.writeBrokenPlist(named: "com.example.broken", in: fixture.userLaunchAgentsURL)
    try fixture.writeLaunchAgent(
        named: "com.example.shared",
        in: fixture.sharedLaunchAgentsURL,
        plist: [
            "Label": "com.example.shared",
            "ProgramArguments": ["/usr/bin/true"],
            "RunAtLoad": true,
        ]
    )
    try fixture.writeLaunchAgent(
        named: "com.example.system",
        in: fixture.systemLaunchAgentsURL,
        plist: [
            "Label": "com.example.system",
            "Program": "/usr/bin/true",
            "KeepAlive": true,
        ]
    )

    try fixture.writeFolderItem(relativePath: "Documents/GitHub/MacHealthOS")
    try fixture.writeFolderItem(relativePath: "Documents/GitHub/PersonalLifeOS")
    try fixture.writeFolderItem(relativePath: "Library/Shortcuts/Shortcut.shortcut")

    let collector = AutomationDiagnosticsCollector(
        configuration: .init(
            homeDirectoryURL: fixture.homeDirectoryURL,
            sharedLaunchAgentsURL: fixture.sharedLaunchAgentsURL,
            systemLaunchAgentsURL: fixture.systemLaunchAgentsURL,
            commandTimeout: 0.5,
            maximumReportedAgentFindings: 10,
            maximumReportedSystemLabels: 4,
            maximumReportedFolderSamples: 4,
            maximumReportedHomebrewServices: 4
        ),
        commandRunner: AutomationStubCommandRunner { command, arguments, _ in
            switch command {
            case .plutil:
                let path = arguments.last ?? ""
                if path.contains("com.example.broken") {
                    return .failure(command, arguments: arguments, standardError: "unexpected character at line 1")
                }

                return .success(command, arguments: arguments, output: "\(path): OK\n")
            case .brew:
                return .success(
                    command,
                    arguments: arguments,
                    output: """
                    Name Status User File
                    watcher error eduardofgiovannini \(fixture.rootURL.appendingPathComponent("watcher.plist").path)
                    postgresql@16 started eduardofgiovannini \(fixture.rootURL.appendingPathComponent("postgresql.plist").path)
                    """
                )
            default:
                return .failure(command, arguments: arguments, standardError: "unexpected command")
            }
        }
    )

    let result = collector.collect()

    #expect(result.diagnostics.status == .warning)
    #expect(result.diagnostics.userLaunchAgents.count == 8)
    #expect(result.diagnostics.sharedLaunchAgents.count == 1)
    #expect(result.diagnostics.systemLaunchAgentCount == 1)
    #expect(result.diagnostics.systemKeepAliveCount == 1)
    #expect(result.diagnostics.systemSampleLabels == ["com.example.system"])
    #expect(result.diagnostics.brokenPlistLabels == ["com.example.broken"])
    #expect(result.diagnostics.missingExecutableLabels == ["com.example.missing"])
    #expect(result.diagnostics.staleLogPathLabels == ["com.example.logs"])
    #expect(result.diagnostics.keepAliveAgentLabels.count == 5)
    #expect(result.diagnostics.keepAliveAgentLabels.contains("com.example.keepalive.one"))
    #expect(result.diagnostics.homebrewServices.count == 2)
    #expect(result.diagnostics.homebrewServices.first?.name == "watcher")
    #expect(result.diagnostics.commonFolders.first(where: { $0.title == "Automation" })?.exists == false)
    #expect(result.diagnostics.commonFolders.first(where: { $0.title == "GitHub" })?.itemCount == 2)
    #expect(result.diagnostics.commonFolders.first(where: { $0.title == "Shortcuts" })?.itemCount == 1)
    #expect(result.diagnostics.issues.contains { $0.title == "Some LaunchAgent files are invalid" })
    #expect(result.diagnostics.issues.contains { $0.title == "Some LaunchAgents point to missing apps or scripts" })
    #expect(result.diagnostics.issues.contains { $0.title == "Some LaunchAgents use missing log folders" })
    #expect(result.diagnostics.issues.contains { $0.title == "Several automation agents are configured to stay running" })
    #expect(result.diagnostics.issues.contains { $0.title == "Some Homebrew services need review" })
    #expect(result.recommendations.contains { $0.title == "Review invalid background item files" })
    #expect(result.recommendations.contains { $0.title == "Review startup items that point to removed apps or scripts" })
    #expect(result.recommendations.contains { $0.title == "Review background items with outdated log destinations" })
    #expect(result.recommendations.contains { $0.title == "Review always-on background items" })
    #expect(result.recommendations.contains { $0.title == "Review Homebrew services that are not in a normal state" })
    #expect(result.recommendations.contains { $0.title == "Review incomplete automation visibility" } == false)
}

@Test func automationCollectorMarksUnavailableVisibilityUnknown() async throws {
    let fixture = try AutomationFixture(createSystemLaunchAgentsDirectory: false)
    defer { fixture.cleanup() }

    try fixture.writeLaunchAgent(
        named: "com.example.valid",
        in: fixture.userLaunchAgentsURL,
        plist: [
            "Label": "com.example.valid",
            "Program": "/usr/bin/true",
        ]
    )

    let collector = AutomationDiagnosticsCollector(
        configuration: .init(
            homeDirectoryURL: fixture.homeDirectoryURL,
            sharedLaunchAgentsURL: fixture.sharedLaunchAgentsURL,
            systemLaunchAgentsURL: fixture.systemLaunchAgentsURL,
            commandTimeout: 0.5
        ),
        commandRunner: AutomationStubCommandRunner { command, arguments, _ in
            switch command {
            case .plutil:
                return .success(command, arguments: arguments, output: "\(arguments.last ?? ""): OK\n")
            case .brew:
                return .launchFailure(command, arguments: arguments, detail: "brew services unavailable")
            default:
                return .failure(command, arguments: arguments, standardError: "unexpected command")
            }
        }
    )

    let result = collector.collect()

    #expect(result.diagnostics.status == .unknown)
    #expect(result.diagnostics.systemLaunchAgentCount == nil)
    #expect(result.diagnostics.commandFailures.count == 1)
    #expect(result.diagnostics.issues.contains { $0.title == "Some automation locations are unavailable" })
    #expect(result.diagnostics.issues.contains { $0.title == "Some automation commands failed" })
    #expect(result.recommendations.contains { $0.title == "Review incomplete automation visibility" })
}

private struct AutomationFixture {
    let rootURL: URL
    let homeDirectoryURL: URL
    let sharedLaunchAgentsURL: URL
    let systemLaunchAgentsURL: URL
    let userLaunchAgentsURL: URL

    init(createSystemLaunchAgentsDirectory: Bool = true) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        homeDirectoryURL = rootURL.appendingPathComponent("home", isDirectory: true)
        sharedLaunchAgentsURL = rootURL.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        systemLaunchAgentsURL = rootURL.appendingPathComponent("System/Library/LaunchAgents", isDirectory: true)
        userLaunchAgentsURL = homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)

        try FileManager.default.createDirectory(at: userLaunchAgentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sharedLaunchAgentsURL, withIntermediateDirectories: true)
        if createSystemLaunchAgentsDirectory {
            try FileManager.default.createDirectory(at: systemLaunchAgentsURL, withIntermediateDirectories: true)
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeLaunchAgent(
        named label: String,
        in directoryURL: URL,
        plist: [String: Any]
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        let fileURL = directoryURL.appendingPathComponent("\(label).plist")
        try data.write(to: fileURL)
    }

    func writeBrokenPlist(
        named label: String,
        in directoryURL: URL
    ) throws {
        let fileURL = directoryURL.appendingPathComponent("\(label).plist")
        try Data("<plist><dict><key>Label</key><string>\(label)</string>".utf8).write(to: fileURL)
    }

    func writeFolderItem(relativePath: String) throws {
        let itemURL = homeDirectoryURL.appendingPathComponent(relativePath)
        let isFile = itemURL.pathExtension.isEmpty == false

        try FileManager.default.createDirectory(
            at: itemURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if isFile {
            try Data("fixture".utf8).write(to: itemURL)
        } else {
            try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
        }
    }
}

private struct AutomationStubCommandRunner: CommandRunning {
    let handler: @Sendable (SafeCommandRunner.Command, [String], TimeInterval) -> SafeCommandRunner.ExecutionResult

    func run(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        timeout: TimeInterval
    ) -> SafeCommandRunner.ExecutionResult {
        handler(command, arguments, timeout)
    }
}

private extension SafeCommandRunner.ExecutionResult {
    static func success(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        output: String
    ) -> SafeCommandRunner.ExecutionResult {
        SafeCommandRunner.ExecutionResult(
            command: command,
            arguments: arguments,
            standardOutput: output,
            standardError: "",
            exitStatus: 0,
            failureReason: nil
        )
    }

    static func failure(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        standardError: String
    ) -> SafeCommandRunner.ExecutionResult {
        SafeCommandRunner.ExecutionResult(
            command: command,
            arguments: arguments,
            standardOutput: "",
            standardError: standardError,
            exitStatus: 1,
            failureReason: .nonZeroExit
        )
    }

    static func launchFailure(
        _ command: SafeCommandRunner.Command,
        arguments: [String],
        detail: String
    ) -> SafeCommandRunner.ExecutionResult {
        SafeCommandRunner.ExecutionResult(
            command: command,
            arguments: arguments,
            standardOutput: "",
            standardError: detail,
            exitStatus: -1,
            failureReason: .launchFailed(detail)
        )
    }
}
