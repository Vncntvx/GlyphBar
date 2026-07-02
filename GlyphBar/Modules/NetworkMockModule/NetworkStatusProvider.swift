import Foundation
import Network

@MainActor
final class NetworkStatusProvider {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.wenjiexu.GlyphBar.network.monitor")

    private var currentPath: NWPath?
    private var successCount = 0
    private var failureCount = 0

    var useMockMode = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.currentPath = path
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    func refresh(moduleID: ModuleID, systemImage: String) async throws -> ModuleSnapshot {
        if useMockMode {
            return try await mockRefresh(moduleID: moduleID, systemImage: systemImage)
        }
        return realSnapshot(moduleID: moduleID)
    }

    func realSnapshot(moduleID: ModuleID) -> ModuleSnapshot {
        let path = currentPath

        let statusText: String
        let statusIcon: String

        switch path?.status {
        case .satisfied:
            statusText = "Connected"
            statusIcon = "wifi"
        case .unsatisfied:
            statusText = "No Connection"
            statusIcon = "wifi.slash"
        case .requiresConnection:
            statusText = "Connecting…"
            statusIcon = "wifi.exclamationmark"
        case nil, _:
            statusText = "Unknown"
            statusIcon = "questionmark.circle"
        }

        let interfaces = path?.availableInterfaces ?? []
        let primaryInterface = interfaces.first
        let interfaceName = primaryInterface?.name ?? "unknown"
        let interfaceType = interfaceTypeName(primaryInterface?.type)
        let isExpensive = path?.isExpensive ?? false

        var meta: [String: String] = [
            "status": statusText,
            "interface": interfaceName,
            "type": interfaceType,
            "isExpensive": isExpensive ? "true" : "false"
        ]

        meta["hostName"] = ProcessInfo.processInfo.hostName

        var signals: [StatusSignal] = []
        if path?.status != .satisfied {
            signals.append(StatusSignal(
                id: "network.offline", title: "Offline",
                message: "Network connection is unavailable.",
                systemImage: "wifi.slash", severity: .critical, priority: 100
            ))
        }

        return ModuleSnapshot(
            id: moduleID,
            title: statusText,
            subtitle: "\(interfaceType) · \(interfaceName)\(isExpensive ? " · Cellular" : "")",
            systemImage: statusIcon,
            signals: signals,
            metrics: [:],
            notes: [],
            metadata: meta
        )
    }

    func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            guard addr.sa_family == UInt8(AF_INET) else { continue }
            guard (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                ptr.pointee.ifa_addr,
                socklen_t(addr.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let name = String(cString: hostname)
            if let ifName = String(cString: ptr.pointee.ifa_name, encoding: .utf8),
               (ifName == "en0" || ifName == "en1") {
                address = name
                break
            }
            if address == nil { address = name }
        }
        return address
    }

    private func mockRefresh(moduleID: ModuleID, systemImage: String) async throws -> ModuleSnapshot {
        try await Task.sleep(for: .milliseconds(250))
        let succeeds = Int.random(in: 0..<100) >= 35
        guard succeeds else {
            failureCount += 1
            throw URLError(.timedOut)
        }
        successCount += 1
        return ModuleSnapshot(
            id: moduleID,
            title: "Mock Online",
            subtitle: "Mock request succeeded (\(successCount) OK, \(failureCount) failed)",
            systemImage: systemImage,
            metrics: ["successes": Double(successCount), "failures": Double(failureCount)],
            metadata: ["mode": "mock", "request": UUID().uuidString]
        )
    }

    private func interfaceTypeName(_ type: NWInterface.InterfaceType?) -> String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .loopback: return "Loopback"
        case .other: return "Other"
        case nil: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}
