import Foundation

enum SecurityFormatters {
    static func enabledStatusString(from value: Bool?) -> String {
        guard let value else {
            return "Unknown"
        }

        return value ? "Enabled" : "Disabled"
    }

    static func updateStatusString(
        count: Int?,
        labels: [String]
    ) -> String {
        guard let count else {
            return "Unknown"
        }

        if count == 0 {
            return "No updates detected"
        }

        if labels.isEmpty {
            return "\(count) update(s) detected"
        }

        return "\(count) update(s): \(labels.prefix(2).joined(separator: ", "))"
    }
}
