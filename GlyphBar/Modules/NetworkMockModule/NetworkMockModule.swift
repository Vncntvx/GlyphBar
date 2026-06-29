import Foundation
import SwiftUI
import Network

@MainActor
final class NetworkMockModule: TypedModuleContribution {
    private let monitor = NWPathMonitor()
    // DispatchQueue is required by NWPathMonitor.start(queue:) — the API demands a
    // dispatch queue and cannot be replaced with Swift concurrency (async/await or Task).
    private let monitorQueue = DispatchQueue(label: "com.wenjiexu.GlyphBar.network.monitor")

    private var currentPath: NWPath?
    private var successCount = 0
    private var failureCount = 0
    private var useMockMode = false

    // P1.13: NWPathMonitor is a built-in module privilege (team-lead approved).
    // No UserDefaults.standard; state is ephemeral.

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

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "networkMock",
        displayName: "Network",
        subtitle: "Connection status and interface info",
        systemImage: "antenna.radiowaves.left.and.right",
        version: "1.1.0",
        author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
        permissions: [],
        defaultRefreshPolicy: .interval(seconds: 30),
        actions: [
            ModuleAction(id: "retry", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh),
            ModuleAction(id: "copyIP", title: "Copy IP", systemImage: "doc.on.doc")
        ],
        widgets: [
            ModuleWidgetDescriptor(
                id: "networkMock.state",
                title: "Network",
                subtitle: "Connection status",
                systemImage: "antenna.radiowaves.left.and.right",
                supportedFamilies: ["small", "medium", "large"]
            )
        ]
    )

    // MARK: - TypedModuleContribution

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition {
        switch command {
        case .refresh:
            do {
                let snap = useMockMode ? try await mockRefresh() : realRefresh()
                return DomainTransition(
                    effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: snap))],
                    health: .healthy,
                    refreshProjection: true
                )
            } catch {
                return DomainTransition(
                    effects: [.showNotice(error.localizedDescription)],
                    health: .degraded(reason: .networkError(error.localizedDescription)),
                    refreshProjection: false
                )
            }
        case .userAction(let actionID, _):
            if actionID == "copyIP", let ip = localIPAddress() {
                return DomainTransition(
                    effects: [.copyToClipboard(ip)],
                    health: nil,
                    refreshProjection: false
                )
            }
            return .empty
        default:
            return .empty
        }
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: realRefresh())
    }

    func statusCandidates() -> [StatusCandidate] {
        let snap = realRefresh()
        return snap.signals.map { signal in
            StatusCandidate(
                id: signal.id,
                sourceModule: manifest.id,
                semanticRole: .alert,
                severity: signal.severity,
                priority: signal.priority,
                text: signal.title,
                icon: signal.systemImage,
                createdAt: snap.timestamp,
                expiresAt: nil,
                interruptPolicy: .preempt,
                trustLevel: .bundled
            )
        }
    }

    func panelContent(context: PanelHostContext) -> some View {
        NetworkPanel(
            snapshot: realRefresh(),
            useMockMode: Binding(
                get: { [weak self] in self?.useMockMode ?? false },
                set: { [weak self] in
                    self?.useMockMode = $0
                    context.dispatch(.refresh(reason: .manual))
                }
            )
        )
    }

    // MARK: - Internals

    private func realRefresh() -> ModuleSnapshot {
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

        if let hostName = ProcessInfo.processInfo.hostName as String? {
            meta["hostName"] = hostName
        }

        var signals: [StatusSignal] = []
        if path?.status != .satisfied {
            signals.append(StatusSignal(
                id: "network.offline", title: "Offline",
                message: "Network connection is unavailable.",
                systemImage: "wifi.slash", severity: .critical, priority: 100
            ))
        }

        return ModuleSnapshot(
            id: manifest.id,
            title: statusText,
            subtitle: "\(interfaceType) · \(interfaceName)\(isExpensive ? " · Cellular" : "")",
            systemImage: statusIcon,
            signals: signals,
            metrics: [:],
            notes: [],
            metadata: meta
        )
    }

    private func mockRefresh() async throws -> ModuleSnapshot {
        try await Task.sleep(for: .milliseconds(250))
        let succeeds = Int.random(in: 0..<100) >= 35
        guard succeeds else {
            failureCount += 1
            throw URLError(.timedOut)
        }
        successCount += 1
        return ModuleSnapshot(
            id: manifest.id,
            title: "Mock Online",
            subtitle: "Mock request succeeded (\(successCount) OK, \(failureCount) failed)",
            systemImage: "antenna.radiowaves.left.and.right",
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

    private func localIPAddress() -> String? {
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
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                       &hostname, socklen_t(hostname.count),
                       nil, 0, NI_NUMERICHOST)
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
}

private struct NetworkPanel: View {
    let snapshot: ModuleSnapshot?
    @Binding var useMockMode: Bool

    var body: some View {
        VStack(spacing: 16) {
                // Status indicator
                HStack(spacing: 12) {
                    Image(systemName: snapshot?.systemImage ?? "questionmark.circle")
                        .font(.largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot?.title ?? "Unknown")
                            .font(.title3.weight(.semibold))
                        if let subtitle = snapshot?.subtitle {
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                Divider()

                // Details
                if let meta = snapshot?.metadata {
                    VStack(spacing: 8) {
                        if let hostName = meta["hostName"] {
                            DetailRow(icon: "desktopcomputer", label: "Host", value: hostName)
                        }
                        if let iface = meta["interface"] {
                            DetailRow(icon: "cable.connector", label: "Interface", value: iface)
                        }
                        if let type = meta["type"] {
                            DetailRow(icon: "wave.3.right", label: "Type", value: type)
                        }
                        if let ip = localIP() {
                            DetailRow(icon: "number", label: "IP Address", value: ip)
                        }
                        if meta["isExpensive"] == "true" {
                            DetailRow(icon: "exclamationmark.triangle", label: "Metered", value: "Cellular / Hotspot")
                        }
                    }
                }

                if let mode = snapshot?.metadata["mode"], mode == "mock" {
                    HStack {
                        Image(systemName: "flask")
                            .foregroundStyle(.orange)
                        Text("Mock Mode Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let successes = snapshot?.metrics["successes"] {
                        GlyphMetricCard(
                            title: "Successful",
                            value: "\(Int(successes))",
                            systemImage: "checkmark.circle"
                        )
                    }
                }

                // Mock mode toggle
                Toggle(isOn: $useMockMode) {
                    Label("Mock Mode", systemImage: "flask")
                }
                .toggleStyle(.switch)
                .font(.callout)
            }
            .padding(14)
    }

    private var statusColor: Color {
        switch snapshot?.metadata["status"] {
        case "Connected": return .green
        case "No Connection": return .red
        case "Connecting…": return .orange
        default: return .secondary
        }
    }

    private func localIP() -> String? {
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
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                       &hostname, socklen_t(hostname.count),
                       nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }
        return address
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }
}
