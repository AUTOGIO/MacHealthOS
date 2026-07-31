import Foundation
import Testing
@testable import MacHealthOS

private let gibibyte: Int64 = 1_073_741_824

@Test func storageCollectorBuildsRealMetricsFromConfiguredHome() async throws {
    let fixture = try StorageFixture()
    defer { fixture.cleanup() }

    try fixture.writeFile(
        relativePath: "Downloads/old-archive.zip",
        size: 4_000,
        modificationDate: fixture.now.addingTimeInterval(-45 * 86_400)
    )
    try fixture.writeFile(
        relativePath: "Downloads/recent.dmg",
        size: 2_000,
        modificationDate: fixture.now.addingTimeInterval(-5 * 86_400)
    )
    try fixture.writeFile(relativePath: ".Trash/deleted.mov", size: 3_000)
    try fixture.writeFile(relativePath: "Library/Caches/cache.db", size: 5_000)
    try fixture.writeFile(relativePath: "Documents/huge-video.mov", size: 6_000)

    let collector = StorageDiagnosticsCollector(
        configuration: .init(
            homeDirectoryURL: fixture.homeDirectoryURL,
            largeFileThresholdBytes: 4_096,
            oldDownloadsThresholdDays: 30,
            maximumReportedLargeFiles: 10,
            maximumReportedOldDownloads: 10,
            fixedVolumeMetrics: .init(totalCapacityBytes: 160 * gibibyte, freeCapacityBytes: 30 * gibibyte)
        )
    )

    let result = collector.collect(now: fixture.now)

    #expect(result.diagnostics.totalCapacityBytes == 160 * gibibyte)
    #expect(result.diagnostics.usedCapacityBytes == 130 * gibibyte)
    #expect(result.diagnostics.freeCapacityBytes == 30 * gibibyte)
    #expect((result.diagnostics.freeCapacityPercent ?? 0) > 18)
    #expect((result.diagnostics.freeCapacityPercent ?? 0) < 19)
    #expect(result.diagnostics.downloadsSizeBytes == 6_000)
    #expect(result.diagnostics.trashSizeBytes == 3_000)
    #expect(result.diagnostics.cachesSizeBytes == 5_000)
    #expect(result.diagnostics.largeFiles.count == 1)
    #expect(result.diagnostics.largeFiles.first?.path.hasSuffix("Documents/huge-video.mov") == true)
    #expect(result.diagnostics.oldDownloads.count == 1)
    #expect(result.diagnostics.oldDownloads.first?.path.hasSuffix("Downloads/old-archive.zip") == true)
    #expect(result.diagnostics.status == .warning)
    #expect(result.diagnostics.issues.contains(where: { $0.title == "Free disk space is getting low" }))
    #expect(result.recommendations.contains(where: { $0.title.hasPrefix("Review files above") }))
    #expect(result.recommendations.contains(where: { $0.title == "Review old Downloads files" }))
}

@Test func storageCollectorMarksUnavailableMetricsUnknown() async throws {
    let fixture = try StorageFixture(createDownloads: false, createTrash: false, createCaches: false)
    defer { fixture.cleanup() }

    let collector = StorageDiagnosticsCollector(
        configuration: .init(
            homeDirectoryURL: fixture.homeDirectoryURL,
            largeFileThresholdBytes: 4_096,
            oldDownloadsThresholdDays: 30,
            fixedVolumeMetrics: .init(totalCapacityBytes: nil, freeCapacityBytes: nil)
        )
    )

    let result = collector.collect(now: fixture.now)

    #expect(result.diagnostics.status == .unknown)
    #expect(result.diagnostics.downloadsSizeBytes == nil)
    #expect(result.diagnostics.trashSizeBytes == nil)
    #expect(result.diagnostics.cachesSizeBytes == nil)
    #expect(result.diagnostics.issues.contains(where: { $0.title == "Some storage metrics are unavailable" }))
}

@Test func storageCollectorSkipsExcludedDirectories() async throws {
    let fixture = try StorageFixture()
    defer { fixture.cleanup() }

    // Large file inside a non-excluded directory should be reported
    try fixture.writeFile(relativePath: "Documents/clean-project/large-file.mov", size: 6_000)

    // Large files inside excluded directories should be skipped
    try fixture.writeFile(relativePath: "Documents/dirty-project/node_modules/bad-dep/large-dependency.js", size: 8_000)
    try fixture.writeFile(relativePath: "Documents/dirty-project/.git/objects/pack/large-pack.pack", size: 9_000)
    try fixture.writeFile(relativePath: "node_modules/ignored-top-level.js", size: 10_000)

    let collector = StorageDiagnosticsCollector(
        configuration: .init(
            homeDirectoryURL: fixture.homeDirectoryURL,
            largeFileThresholdBytes: 4_096,
            oldDownloadsThresholdDays: 30,
            maximumReportedLargeFiles: 10,
            maximumReportedOldDownloads: 10,
            fixedVolumeMetrics: .init(totalCapacityBytes: 160 * gibibyte, freeCapacityBytes: 30 * gibibyte)
        )
    )

    let result = collector.collect(now: fixture.now)

    // Only the clean large file should be reported
    #expect(result.diagnostics.largeFiles.count == 1)
    #expect(result.diagnostics.largeFiles.first?.path.hasSuffix("Documents/clean-project/large-file.mov") == true)
}

private struct StorageFixture {
    let homeDirectoryURL: URL
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    init(
        createDownloads: Bool = true,
        createTrash: Bool = true,
        createCaches: Bool = true
    ) throws {
        homeDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: homeDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: homeDirectoryURL.appendingPathComponent("Documents", isDirectory: true),
            withIntermediateDirectories: true
        )

        if createDownloads {
            try FileManager.default.createDirectory(
                at: homeDirectoryURL.appendingPathComponent("Downloads", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        if createTrash {
            try FileManager.default.createDirectory(
                at: homeDirectoryURL.appendingPathComponent(".Trash", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        if createCaches {
            try FileManager.default.createDirectory(
                at: homeDirectoryURL
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Caches", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: homeDirectoryURL)
    }

    func writeFile(
        relativePath: String,
        size: Int,
        modificationDate: Date? = nil
    ) throws {
        let fileURL = homeDirectoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = Data(repeating: 0x5A, count: size)
        try data.write(to: fileURL)

        if let modificationDate {
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: fileURL.path
            )
        }
    }
}
