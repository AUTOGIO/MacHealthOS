import Foundation

enum TimestampFormatter {
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private static let reportFileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    static func displayString(from date: Date?) -> String {
        guard let date else {
            return "Not run yet"
        }

        return displayFormatter.string(from: date)
    }

    static func fileNameString(from date: Date) -> String {
        fileNameFormatter.string(from: date)
    }

    static func reportFileNameString(from date: Date) -> String {
        reportFileNameFormatter.string(from: date)
    }

    static func iso8601String(from date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
