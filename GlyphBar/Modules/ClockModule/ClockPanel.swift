import SwiftUI

struct ClockPanel: View {
    let snapshot: ModuleSnapshot?
    @Binding var uses24HourClock: Bool
    @Binding var showSeconds: Bool
    @Binding var worldTimezones: [String]
    let availableTimezones: [ClockTimezoneOption]

    @State private var showTimezonePicker = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(snapshot?.title ?? "--:--")
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(snapshot?.subtitle ?? "Loading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let tz = snapshot?.metadata["tzAbbreviation"] {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                    Text(tz)
                        .font(.caption.weight(.medium))
                    if let offset = snapshot?.metrics["offset"] {
                        Text(String(format: "UTC%+.0f", offset))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(.thinMaterial, in: Capsule())
            }

            HStack(spacing: 12) {
                Toggle(isOn: $uses24HourClock) {
                    Label("24h", systemImage: "textformat.123")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button)
                .controlSize(.small)

                Toggle(isOn: $showSeconds) {
                    Label("Seconds", systemImage: "stopwatch")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }

            if !worldTimezones.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("World Clocks", systemImage: "globe")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button {
                            showTimezonePicker.toggle()
                        } label: {
                            Image(systemName: showTimezonePicker ? "chevron.up" : "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(worldTimezones, id: \.self) { tzID in
                        WorldClockRow(
                            timezoneID: tzID,
                            label: ClockTimezoneCatalog.label(for: tzID),
                            uses24HourClock: uses24HourClock,
                            onRemove: {
                                worldTimezones.removeAll { $0 == tzID }
                            }
                        )
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            if showTimezonePicker {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Timezone")
                        .font(.caption.weight(.semibold))
                    ForEach(availableTimezones, id: \.id) { tz in
                        if !worldTimezones.contains(tz.id) {
                            Button {
                                worldTimezones.append(tz.id)
                                showTimezonePicker = false
                            } label: {
                                HStack {
                                    Text(tz.label)
                                    Spacer()
                                    Text(worldTimeText(for: tz.id))
                                        .foregroundStyle(.secondary)
                                        .font(.caption.monospacedDigit())
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(14)
    }

    private func worldTimeText(for tzID: String) -> String {
        guard let tz = TimeZone(identifier: tzID) else { return "--:--" }
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.setLocalizedDateFormatFromTemplate(uses24HourClock ? "HHmm" : "hmma")
        return fmt.string(from: Date())
    }
}

private struct WorldClockRow: View {
    let timezoneID: String
    let label: String
    let uses24HourClock: Bool
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .frame(width: 6, height: 6)
                .foregroundStyle(.green)
            Text(label)
                .font(.callout)
            Spacer()
            Text(timeText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var timeText: String {
        guard let tz = TimeZone(identifier: timezoneID) else { return "--:--" }
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.setLocalizedDateFormatFromTemplate(uses24HourClock ? "HHmm" : "hmma")
        return fmt.string(from: Date())
    }
}
