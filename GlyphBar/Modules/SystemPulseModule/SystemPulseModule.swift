import Foundation
import SwiftUI

@MainActor
final class SystemPulseModule: TypedModuleContribution {
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    private let systemMetrics: SystemMetricsCapability?

    init(systemMetrics: SystemMetricsCapability? = nil) {
        self.systemMetrics = systemMetrics
    }

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "systemPulse",
        displayName: "System Pulse",
        subtitle: "Real-time CPU, memory, storage, and battery",
        systemImage: "waveform.path.ecg",
        version: "1.1.0",
        author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .deepLinks],
        permissions: [.systemMetrics],
        defaultRefreshPolicy: .interval(seconds: 5),
        actions: [
            ModuleAction(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh)
        ],
        widgets: [
            ModuleWidgetDescriptor(
                id: "systemPulse.metrics",
                title: "System Pulse",
                subtitle: "System metrics",
                systemImage: "waveform.path.ecg",
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
            return DomainTransition(
                effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
                health: .healthy,
                refreshProjection: true
            )
        default:
            return .empty
        }
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: buildSnapshot())
    }

    func statusCandidates() -> [StatusCandidate] {
        let snap = buildSnapshot()
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
        SystemPulsePanel(snapshot: buildSnapshot())
    }

    // MARK: - Internals

    private func buildSnapshot() -> ModuleSnapshot {
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
            id: manifest.id,
            title: "CPU \(Int(cpu))%",
            subtitle: "Memory \(Int(memory))% · Storage \(Int(storage))%",
            systemImage: manifest.systemImage,
            signals: signals,
            metrics: ["cpu": cpu, "memory": memory, "storage": storage, "uptime": uptime],
            metadata: ["thermal": thermal]
        )
    }

    // MARK: - Real CPU (built-in module privilege: Mach API)

    private func realCPUUsage() -> Double {
        var count: mach_msg_type_number_t = 0
        var ticks: host_cpu_load_info_data_t = host_cpu_load_info_data_t()
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

    // MARK: - Real Memory (via capability when available)

    private func realMemoryUsage() -> Double {
        if let cap = systemMetrics {
            let (used, total) = cap.memoryUsage()
            guard total > 0 else { return 0 }
            return min(100, max(0, Double(used) / Double(total) * 100))
        }
        // Fallback: direct Mach call (only if capability not injected)
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

    // MARK: - Storage (via capability when available)

    private func storageUsage() -> Double {
        if let cap = systemMetrics, let (used, total) = cap.diskUsage(), total > 0 {
            return max(0, min(100, Double(used) / Double(total) * 100))
        }
        // Fallback
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity,
              total > 0 else {
            return 0
        }
        return max(0, min(100, (1 - Double(available) / Double(total)) * 100))
    }

    // MARK: - Thermal (built-in privilege: ProcessInfo)

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

// MARK: - Panel View

private struct SystemPulsePanel: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        VStack(spacing: 20) {
                // Main metrics ring charts
                HStack(alignment: .top, spacing: 16) {
                    MetricRing(
                        title: "CPU",
                        value: snapshot?.metrics["cpu"],
                        systemImage: "cpu",
                        color: cpuColor
                    )
                    MetricRing(
                        title: "Memory",
                        value: snapshot?.metrics["memory"],
                        systemImage: "memorychip",
                        color: memoryColor
                    )
                    MetricRing(
                        title: "Storage",
                        value: snapshot?.metrics["storage"],
                        systemImage: "internaldrive",
                        color: storageColor
                    )
                }

                Divider()

                // Secondary info
                HStack(spacing: 12) {
                    // Thermal
                    VStack(spacing: 4) {
                        Image(systemName: thermalIcon)
                            .font(.title3)
                            .foregroundStyle(thermalColor)
                        Text(thermalLabel)
                            .font(.caption.weight(.medium))
                        Text("Thermal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Uptime
                    VStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(uptimeText)
                            .font(.caption.weight(.medium))
                        Text("Uptime")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // High load warning
                if let signals = snapshot?.signals, !signals.isEmpty {
                    ForEach(signals) { signal in
                        HStack(spacing: 8) {
                            Image(systemName: signal.systemImage)
                                .foregroundStyle(signal.severity == .critical ? .red : .orange)
                            Text(signal.message)
                                .font(.caption)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(signal.severity == .critical ? Color.red.opacity(0.1) : Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(14)
    }

    // MARK: - Colors

    private var cpuColor: Color {
        guard let v = snapshot?.metrics["cpu"] else { return .secondary }
        if v > 90 { return .red }
        if v > 70 { return .orange }
        return .green
    }

    private var memoryColor: Color {
        guard let v = snapshot?.metrics["memory"] else { return .secondary }
        if v > 90 { return .red }
        if v > 70 { return .orange }
        return .green
    }

    private var storageColor: Color {
        guard let v = snapshot?.metrics["storage"] else { return .secondary }
        if v > 90 { return .red }
        if v > 75 { return .orange }
        return .green
    }

    private var thermalIcon: String {
        switch snapshot?.metadata["thermal"] {
        case "Fair": return "thermometer.medium"
        case "Serious": return "thermometer.high"
        case "Critical": return "thermometer.snowflake"
        default: return "thermometer.low"
        }
    }

    private var thermalColor: Color {
        switch snapshot?.metadata["thermal"] {
        case "Fair": return .yellow
        case "Serious": return .orange
        case "Critical": return .red
        default: return .green
        }
    }

    private var thermalLabel: String {
        snapshot?.metadata["thermal"] ?? "Nominal"
    }

    private var uptimeText: String {
        guard let uptime = snapshot?.metrics["uptime"] else { return "--" }
        let hours = Int(uptime) / 3600
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}

// MARK: - Circular Progress Ring

private struct MetricRing: View {
    let title: String
    let value: Double?
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat((value ?? 0) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: value)
                VStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(value ?? 0))%")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(color)
                }
            }
            .frame(width: 72, height: 72)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
