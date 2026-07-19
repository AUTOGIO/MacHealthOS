import Foundation

struct MaintenanceService: Sendable {
    struct Configuration: Sendable {
        var homeDirectoryURL: URL
        var maximumReportedCacheFolders: Int

        init(
            homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
            maximumReportedCacheFolders: Int = 40
        ) {
            self.homeDirectoryURL = homeDirectoryURL
            self.maximumReportedCacheFolders = maximumReportedCacheFolders
        }

        var trashDirectoryURL: URL {
            homeDirectoryURL.appendingPathComponent(".Trash", isDirectory: true)
        }

        var cachesDirectoryURL: URL {
            homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }

        var downloadsDirectoryURL: URL {
            homeDirectoryURL.appendingPathComponent("Downloads", isDirectory: true)
        }
    }

    struct ExecutionResult: Equatable, Sendable {
        let result: MaintenanceActionRecord.Result
        let details: String
        let lastMaintenanceDate: Date?
    }

    enum Error: LocalizedError {
        case trashDirectoryMissing
        case cachesDirectoryMissing
        case noCacheFoldersSelected
        case cacheFolderOutsideUserCaches(String)

        var errorDescription: String? {
            switch self {
            case .trashDirectoryMissing:
                "The user Trash folder could not be found."
            case .cachesDirectoryMissing:
                "The user Caches folder could not be found."
            case .noCacheFoldersSelected:
                "No cache folders were selected."
            case .cacheFolderOutsideUserCaches(let path):
                "The selected cache folder is outside ~/Library/Caches: \(path)"
            }
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func availableCacheFolders() -> [UserCacheFolderSnapshot] {
        let cachesDirectoryURL = configuration.cachesDirectoryURL
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: cachesDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: cachesDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return children
            .filter { url in
                ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == true
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .prefix(configuration.maximumReportedCacheFolders)
            .map { url in
                UserCacheFolderSnapshot(
                    path: url.path,
                    name: url.lastPathComponent,
                    estimatedSizeBytes: directorySize(at: url)
                )
            }
    }

    func emptyTrash(now: Date = Date()) throws -> ExecutionResult {
        let trashDirectoryURL = configuration.trashDirectoryURL
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: trashDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Error.trashDirectoryMissing
        }

        let removedCount = try clearContents(of: trashDirectoryURL)
        return ExecutionResult(
            result: .completed,
            details: removedCount == 0
                ? "The user Trash was already empty."
                : "Removed \(removedCount) item(s) from the user Trash.",
            lastMaintenanceDate: now
        )
    }

    func clearCacheFolders(
        _ folders: [UserCacheFolderSnapshot],
        now: Date = Date()
    ) throws -> ExecutionResult {
        guard !folders.isEmpty else {
            throw Error.noCacheFoldersSelected
        }

        let cachesRoot = configuration.cachesDirectoryURL.standardizedFileURL.path + "/"
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: configuration.cachesDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Error.cachesDirectoryMissing
        }

        var clearedFolderCount = 0
        var removedItemCount = 0

        for folder in folders {
            let folderURL = URL(fileURLWithPath: folder.path).standardizedFileURL
            let folderPath = folderURL.path
            guard folderPath.hasPrefix(cachesRoot) else {
                throw Error.cacheFolderOutsideUserCaches(folderPath)
            }

            if fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue {
                removedItemCount += try clearContents(of: folderURL)
                clearedFolderCount += 1
            }
        }

        return ExecutionResult(
            result: .completed,
            details: "Cleared \(removedItemCount) item(s) across \(clearedFolderCount) cache folder(s).",
            lastMaintenanceDate: now
        )
    }

    func dnsFlushCommand() -> String {
        "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
    }

    func spotlightReindexCommand() -> String {
        "sudo mdutil -E /"
    }

    private func clearContents(of directoryURL: URL) throws -> Int {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for childURL in contents {
            try fileManager.removeItem(at: childURL)
        }

        return contents.count
    }

    private func directorySize(at directoryURL: URL) -> Int64? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                totalSize += Int64(values?.fileSize ?? 0)
            }
        }

        return totalSize
    }
}
