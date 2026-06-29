import Foundation

/// System-metrics capability. Replaces direct `ProcessInfo` / `URLSession` /
/// `FileManager` system-stat usage inside modules.
@MainActor
final class SystemMetricsCapability: Capability {
    static let declaredKey: CapabilityKey = .systemMetrics

    func cpuUsage() -> Double {
        // P1 returns a best-effort snapshot via host_processor_info would require
        // Mach imports; we expose a stable API and return 0 here so callers can
        // migrate. P2 will wire a real implementation.
        return 0
    }

    func memoryUsage() -> (used: UInt64, total: UInt64) {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let used: UInt64
        if result == KERN_SUCCESS {
            used = taskInfo.phys_footprint
        } else {
            used = 0
        }
        let total = ProcessInfo.processInfo.physicalMemory
        return (used, total)
    }

    func diskUsage() -> (used: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            return (total - available, total)
        } catch {
            return nil
        }
    }

    func networkInterfaces() -> [NetworkInterface] {
        var results: [NetworkInterface] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return results
        }
        defer { freeifaddrs(first) }
        var cursor = first
        while let pointer = Optional(cursor) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            let flags = interface.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            var ipAddress: String?
            if let addr = interface.ifa_addr {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let addrSize = addr.pointee.sa_len
                if getnameinfo(addr, socklen_t(addrSize), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    ipAddress = String(cString: hostname)
                }
            }
            results.append(NetworkInterface(
                name: name,
                isUp: isUp,
                isLoopback: isLoopback,
                ipAddress: ipAddress
            ))
            cursor = interface.ifa_next
        }
        return results
    }
}

struct NetworkInterface: Sendable {
    let name: String
    let isUp: Bool
    let isLoopback: Bool
    let ipAddress: String?
}
