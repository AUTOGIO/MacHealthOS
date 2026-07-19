import Foundation

enum StorageFormatters {
    private static func makeByteCountFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    static func byteCountString(from bytes: Int64?) -> String {
        guard let bytes else {
            return "Unknown"
        }

        return makeByteCountFormatter().string(fromByteCount: bytes)
    }

    static func percentageString(from percentage: Double?) -> String {
        guard let percentage else {
            return "Unknown"
        }

        return String(format: "%.1f%%", percentage)
    }

    static func dateString(from date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }

        return makeDateFormatter().string(from: date)
    }
}
