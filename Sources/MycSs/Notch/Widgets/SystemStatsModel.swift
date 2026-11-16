import AppKit
import IOKit.ps
import Observation

/// Battery, processor and memory, for the notch.
@MainActor
@Observable
final class SystemStatsModel {

    private(set) var batteryPercent: Int?
    private(set) var isCharging = false
    private(set) var isOnAC = false
    /// Minutes until empty or full, when the system knows.
    private(set) var minutesRemaining: Int?
    /// Processor use, 0 to 1.
    private(set) var cpu: Double = 0
    /// Memory in use, in gigabytes, and the total.
    private(set) var memoryUsedGB: Double = 0
    private(set) var memoryTotalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    @ObservationIgnored private var lastCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    /// Reads everything. Cheap, but not meant for more than once or twice a second.
    func refresh() {
        readBattery()
        readCPU()
        readMemory()
    }

    // MARK: - Battery

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            batteryPercent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : nil
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            isOnAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = description[key] as? Int
            minutesRemaining = (minutes ?? -1) > 0 ? minutes : nil
            return
        }
        // A desktop Mac has no battery.
        batteryPercent = nil
    }

    // MARK: - Processor

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return }
        let now = (
            user: info.cpu_ticks.0, system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2, nice: info.cpu_ticks.3
        )
        defer { lastCPUTicks = now }
        guard let last = lastCPUTicks else { return }
        let user = Double(now.user &- last.user)
        let system = Double(now.system &- last.system)
        let idle = Double(now.idle &- last.idle)
        let nice = Double(now.nice &- last.nice)
        let total = user + system + idle + nice
        cpu = total > 0 ? (user + system + nice) / total : 0
    }

    // MARK: - Memory

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return }
        let pageSize = Double(vm_kernel_page_size)
        // What Activity Monitor calls "memory used": app, wired and compressed.
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        memoryUsedGB = used / 1_073_741_824
    }
}
