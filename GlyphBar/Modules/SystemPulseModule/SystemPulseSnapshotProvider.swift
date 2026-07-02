import Foundation

@MainActor
final class SystemPulseSnapshotProvider {
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private let systemMetrics: SystemMetricsCapability?

    init(systemMetrics: SystemMetricsCapability? = nil) {
        self.systemMetrics = systemMetrics
    }

    func buildSnapshot(moduleID: ModuleID, systemImage: String) -> ModuleSnapshot {
        let cpu = realCPUUsage()
        let memory = realMemoryUsage()
        let storage = storageUsage()
        let thermal = thermalDescription()
        let uptime = ProcessInfo.processInfo.systemUptime

        let highestMetric = max(cpu, memory, storage)

        var signals: [StatusSignal] = []
        if highestMetric > 90 {
            signals.append(StatusSignal(
                id: "systemPulse.critical", title: "Critical Load",
                message: "One or more system metrics are above 90%.",
                systemImage: "exclamationmark.triangle.fill", severity: .critical, priority: 100
            ))
        } else if highestMetric > 75 {
            signals.append(StatusSignal(
                id: "systemPulse.warning", title: "High Load",
                message: "One or more system metrics are above 75%.",
                systemImage: "exclamationmark.triangle", severity: .warning, priority: 40
            ))
        }

        return ModuleSnapshot(
            id: moduleID,
            title: "CPU \(Int(cpu))%",
            subtitle: "Memory \(Int(memory))% · Storage \(Int(storage))%",
            systemImage: systemImage,
            signals: signals,
            metrics: ["cpu": cpu, "memory": memory, "storage": storage, "uptime": uptime],
            metadata: ["thermal": thermal]
        )
    }

    private func realCPUUsage() -> Double {
        var count: mach_msg_type_number_t = 0
        var ticks = host_cpu_load_info_data_t()
        let size = MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        let result = withUnsafeMutablePointer(to: &ticks) {
            $0.withMemoryRebound(to: integer_t.self, capacity: size) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = UInt64(ticks.cpu_ticks.0)
        let system = UInt64(ticks.cpu_ticks.1)
        let idle = UInt64(ticks.cpu_ticks.2)
        let nice = UInt64(ticks.cpu_ticks.3)

        defer { previousCPUTicks = (user, system, idle, nice) }

        guard let prev = previousCPUTicks else { return 0 }

        let userDelta = user - prev.user
        let systemDelta = system - prev.system
        let idleDelta = idle - prev.idle
        let niceDelta = nice - prev.nice

        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return 0 }

        let used = userDelta + systemDelta + niceDelta
        return min(100, max(0, Double(used) / Double(totalDelta) * 100))
    }

    private func realMemoryUsage() -> Double {
        if let cap = systemMetrics {
            let (used, total) = cap.memoryUsage()
            guard total > 0 else { return 0 }
            return min(100, max(0, Double(used) / Double(total) * 100))
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let active = UInt64(stats.active_count) * UInt64(pageSize)
        let wired = UInt64(stats.wire_count) * UInt64(pageSize)
        let compressed = UInt64(stats.compressor_page_count) * UInt64(pageSize)
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        let used = active + wired + compressed
        return min(100, max(0, Double(used) / Double(total) * 100))
    }

    private func storageUsage() -> Double {
        if let cap = systemMetrics, let (used, total) = cap.diskUsage(), total > 0 {
            return max(0, min(100, Double(used) / Double(total) * 100))
        }

        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ),
        let available = values.volumeAvailableCapacityForImportantUsage,
        let total = values.volumeTotalCapacity,
        total > 0 else {
            return 0
        }
        return max(0, min(100, (1 - Double(available) / Double(total)) * 100))
    }

    private func thermalDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
