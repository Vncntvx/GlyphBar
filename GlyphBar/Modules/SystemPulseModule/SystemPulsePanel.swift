import SwiftUI

struct SystemPulsePanel: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        VStack(spacing: 20) {
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

            HStack(spacing: 12) {
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
                    .background(
                        signal.severity == .critical ? Color.red.opacity(0.1) : Color.orange.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }
        }
        .padding(14)
    }

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
