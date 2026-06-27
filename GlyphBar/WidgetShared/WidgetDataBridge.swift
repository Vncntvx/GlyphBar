import Foundation

final class WidgetDataBridge {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = AppGroup.defaults()) {
        self.defaults = defaults
    }

    func write(_ snapshot: WidgetModuleSnapshot, for moduleID: String) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: key(for: moduleID))
    }

    func read(moduleID: String) -> WidgetModuleSnapshot? {
        guard let data = defaults.data(forKey: key(for: moduleID)) else {
            return nil
        }

        return try? decoder.decode(WidgetModuleSnapshot.self, from: data)
    }

    func remove(moduleID: String) {
        defaults.removeObject(forKey: key(for: moduleID))
    }

    func publish(_ snapshot: ModuleSnapshot) {
        write(Self.widgetSnapshot(from: snapshot), for: snapshot.id)
    }

    static func widgetSnapshot(from snapshot: ModuleSnapshot) -> WidgetModuleSnapshot {
        let severity = snapshot.signals.map(\.severity).max() ?? .normal
        let widgetSeverity: WidgetSeverity
        switch severity {
        case .normal: widgetSeverity = .normal
        case .info: widgetSeverity = .info
        case .warning: widgetSeverity = .warning
        case .critical: widgetSeverity = .critical
        }

        let metrics = snapshot.metrics
            .sorted { $0.key < $1.key }
            .map { WidgetMetric(id: $0.key, title: $0.key.capitalized, value: formatted($0.value), symbol: "chart.bar") }

        let unavailableReason: String?
        switch snapshot.freshness {
        case .fresh, .stale:
            unavailableReason = nil
        case .unavailable(let reason):
            unavailableReason = reason
        }

        return WidgetModuleSnapshot(
            id: snapshot.id,
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            symbol: snapshot.systemImage,
            severity: widgetSeverity,
            metrics: metrics,
            notes: snapshot.notes,
            timestamp: snapshot.timestamp,
            unavailableReason: unavailableReason
        )
    }

    static func unavailableSnapshot(moduleID: String, title: String, symbol: String) -> WidgetModuleSnapshot {
        WidgetModuleSnapshot(
            id: moduleID,
            title: title,
            subtitle: "Open GlyphBar to refresh",
            symbol: symbol,
            severity: .warning,
            metrics: [],
            notes: [],
            timestamp: Date(),
            unavailableReason: "No cached snapshot"
        )
    }

    private func key(for moduleID: String) -> String {
        "widget.snapshot.\(moduleID)"
    }

    private static func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }

        return String(format: "%.1f", value)
    }
}
