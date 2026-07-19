import Darwin
import Foundation

struct SystemProfileProvider: Sendable {
    func snapshot() -> MachineProfile {
        MachineProfile(
            machineName: Host.current().localizedName ?? "Unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareArchitecture: currentArchitecture()
        )
    }

    private func currentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { machinePointer in
                String(cString: machinePointer)
            }
        }
    }
}
