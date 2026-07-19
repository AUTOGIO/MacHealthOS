import Foundation
import Testing
@testable import MacHealthOS

@Test func maintenanceServiceEmptiesOnlyUserTrashContents() async throws {
    let fixture = try MaintenanceFixture()
    defer {
        fixture.cleanup()
    }

    try fixture.writeFile(relativePath: ".Trash/old.txt", contents: "trash")

    let service = MaintenanceService(
        configuration: .init(homeDirectoryURL: fixture.homeDirectoryURL)
    )

    let result = try service.emptyTrash(now: fixture.now)
    let trashContents = try FileManager.default.contentsOfDirectory(
        atPath: fixture.homeDirectoryURL.appendingPathComponent(".Trash").path
    )

    #expect(result.result == .completed)
    #expect(result.lastMaintenanceDate == fixture.now)
    #expect(FileManager.default.fileExists(atPath: fixture.homeDirectoryURL.appendingPathComponent(".Trash").path))
    #expect(trashContents.isEmpty)
}

@Test func maintenanceServiceClearsSelectedCacheFolderContents() async throws {
    let fixture = try MaintenanceFixture()
    defer {
        fixture.cleanup()
    }

    try fixture.writeFile(relativePath: "Library/Caches/AppCache/cache.db", contents: "cache")
    try fixture.writeFile(relativePath: "Library/Caches/OtherCache/keep.txt", contents: "keep")

    let service = MaintenanceService(
        configuration: .init(homeDirectoryURL: fixture.homeDirectoryURL)
    )
    let folders = service.availableCacheFolders()
    let selected = try #require(folders.first(where: { $0.name == "AppCache" }))

    let result = try service.clearCacheFolders([selected], now: fixture.now)
    let appCacheContents = try FileManager.default.contentsOfDirectory(
        atPath: fixture.homeDirectoryURL.appendingPathComponent("Library/Caches/AppCache").path
    )
    let otherCacheContents = try FileManager.default.contentsOfDirectory(
        atPath: fixture.homeDirectoryURL.appendingPathComponent("Library/Caches/OtherCache").path
    )

    #expect(result.result == .completed)
    #expect(result.lastMaintenanceDate == fixture.now)
    #expect(appCacheContents.isEmpty)
    #expect(otherCacheContents.count == 1)
}

private struct MaintenanceFixture {
    let homeDirectoryURL: URL
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        homeDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: homeDirectoryURL.appendingPathComponent(".Trash", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: homeDirectoryURL)
    }

    func writeFile(relativePath: String, contents: String) throws {
        let fileURL = homeDirectoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
    }
}
