import Foundation

struct StorageDiagnostics: Codable, Equatable, Sendable {
    struct FileFinding: Codable, Equatable, Sendable, Identifiable {
        let path: String
        let sizeBytes: Int64
        let contentModificationDate: Date?

        var id: String {
            path
        }
    }

    struct ScanError: Codable, Equatable, Sendable, Identifiable {
        let path: String
        let operation: String
        let message: String

        var id: String {
            "\(operation):\(path)"
        }
    }

    var status: HealthStatus
    var totalCapacityBytes: Int64?
    var usedCapacityBytes: Int64?
    var freeCapacityBytes: Int64?
    var freeCapacityPercent: Double?
    var downloadsSizeBytes: Int64?
    var trashSizeBytes: Int64?
    var cachesSizeBytes: Int64?
    var largeFileThresholdBytes: Int64
    var oldDownloadsThresholdDays: Int
    var largeFiles: [FileFinding]
    var oldDownloads: [FileFinding]
    var scanErrors: [ScanError]
    var issues: [HealthIssue]

    init(
        status: HealthStatus = .unknown,
        totalCapacityBytes: Int64? = nil,
        usedCapacityBytes: Int64? = nil,
        freeCapacityBytes: Int64? = nil,
        freeCapacityPercent: Double? = nil,
        downloadsSizeBytes: Int64? = nil,
        trashSizeBytes: Int64? = nil,
        cachesSizeBytes: Int64? = nil,
        largeFileThresholdBytes: Int64 = 1_000_000_000,
        oldDownloadsThresholdDays: Int = 30,
        largeFiles: [FileFinding] = [],
        oldDownloads: [FileFinding] = [],
        scanErrors: [ScanError] = [],
        issues: [HealthIssue] = []
    ) {
        self.status = status
        self.totalCapacityBytes = totalCapacityBytes
        self.usedCapacityBytes = usedCapacityBytes
        self.freeCapacityBytes = freeCapacityBytes
        self.freeCapacityPercent = freeCapacityPercent
        self.downloadsSizeBytes = downloadsSizeBytes
        self.trashSizeBytes = trashSizeBytes
        self.cachesSizeBytes = cachesSizeBytes
        self.largeFileThresholdBytes = largeFileThresholdBytes
        self.oldDownloadsThresholdDays = oldDownloadsThresholdDays
        self.largeFiles = largeFiles
        self.oldDownloads = oldDownloads
        self.scanErrors = scanErrors
        self.issues = issues
    }
}
