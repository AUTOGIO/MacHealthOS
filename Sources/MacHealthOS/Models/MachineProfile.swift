import Foundation

struct MachineProfile: Codable, Equatable, Sendable {
    var machineName: String
    var macOSVersion: String
    var hardwareArchitecture: String

    static let unknown = MachineProfile(
        machineName: "Unknown",
        macOSVersion: "Unknown",
        hardwareArchitecture: "Unknown"
    )
}
