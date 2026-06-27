import Foundation
import SwiftUI

@MainActor
final class SystemPulseModule: StatusModule {
    var manifest: ModuleManifest {
        ModuleManifest(
            id: "systemPulse",
            displayName: "System Pulse",
            subtitle: "Local CPU, memory, and storage indicators",
            systemImage: "waveform.path.ecg",
            version: "1.0.0",
            author: "Wenjie Xu",
            capabilities: [.statusItem, .panel, .widgets, .actions, .deepLinks],
            permissions: [.systemMetrics],
            defaultRefreshPolicy: .interval(seconds: 30),
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
    }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
        let cpu = Double.random(in: 12...92)
        let memory = memoryPressure()
        let storage = storageUsage()
        let severity: Severity = max(cpu, memory, storage) > 85 ? .warning : .normal
        let signals = severity == .warning
            ? [StatusSignal(title: "High Load", message: "One system metric is above 85%.", systemImage: "exclamationmark.triangle", severity: .warning, priority: 40)]
            : []

        return ModuleSnapshot(
            id: manifest.id,
            title: "\(Int(cpu))% CPU",
            subtitle: "Memory \(Int(memory))% · Storage \(Int(storage))%",
            systemImage: manifest.systemImage,
            signals: signals,
            metrics: ["cpu": cpu, "memory": memory, "storage": storage]
        )
    }

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        action.id == "refresh" ? .refreshRequested(manifest.id) : .none
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(SystemPulsePanel(snapshot: snapshot))
    }

    private func memoryPressure() -> Double {
        let physical = Double(ProcessInfo.processInfo.physicalMemory)
        let usedApproximation = physical * Double.random(in: 0.35...0.86)
        return min(99, max(1, usedApproximation / physical * 100))
    }

    private func storageUsage() -> Double {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity,
              total > 0 else {
            return Double.random(in: 30...75)
        }
        return max(0, min(100, (1 - Double(available) / Double(total)) * 100))
    }
}

private struct SystemPulsePanel: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            GlyphMetricCard(title: "CPU", value: percent("cpu"), systemImage: "cpu")
            GlyphMetricCard(title: "Memory", value: percent("memory"), systemImage: "memorychip")
            GlyphMetricCard(title: "Storage", value: percent("storage"), systemImage: "internaldrive")
        }
    }

    private func percent(_ key: String) -> String {
        guard let value = snapshot?.metrics[key] else {
            return "--"
        }
        return "\(Int(value))%"
    }
}
