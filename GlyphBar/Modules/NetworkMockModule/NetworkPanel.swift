import SwiftUI

struct NetworkPanel: View {
    let snapshot: ModuleSnapshot?
    let localIPAddress: String?
    @Binding var useMockMode: Bool

    var body: some View {
        VStack(spacing: 16) {
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
                    if let localIPAddress {
                        DetailRow(icon: "number", label: "IP Address", value: localIPAddress)
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
