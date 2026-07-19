import Foundation

enum PerformanceFormatters {
    static func durationString(from seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "Unknown"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll

        return formatter.string(from: seconds) ?? "\(Int(seconds.rounded())) sec"
    }

    static func cpuLoadString(from percentage: Double?) -> String {
        guard let percentage else {
            return "Unknown"
        }

        return String(format: "%.1f%%", percentage)
    }
}
