import Foundation

struct StatusItemPresentation: Equatable {
    var title: String
    var systemImage: String
    var severity: Severity
    var tooltip: String
}

struct StatusComposer {
    func compose(snapshots: [ModuleID: ModuleSnapshot], primaryModuleID: ModuleID?) -> StatusItemPresentation {
        let signals = snapshots.values.flatMap(\.signals)
        if let critical = signals
            .filter({ $0.severity == .critical })
            .sorted(by: sortSignals)
            .first {
            return StatusItemPresentation(
                title: critical.title,
                systemImage: critical.systemImage,
                severity: .critical,
                tooltip: critical.message
            )
        }

        let warnings = signals
            .filter { $0.severity == .warning }
            .sorted(by: sortSignals)

        if warnings.count > 1 {
            return StatusItemPresentation(
                title: "\(warnings.count) warnings",
                systemImage: "exclamationmark.triangle",
                severity: .warning,
                tooltip: warnings.map(\.title).joined(separator: ", ")
            )
        }

        if let warning = warnings.first {
            return StatusItemPresentation(
                title: warning.title,
                systemImage: warning.systemImage,
                severity: .warning,
                tooltip: warning.message
            )
        }

        if let primaryModuleID,
           let primary = snapshots[primaryModuleID] {
            return StatusItemPresentation(
                title: primary.title,
                systemImage: primary.systemImage,
                severity: .normal,
                tooltip: primary.subtitle
            )
        }

        return StatusItemPresentation(
            title: "GlyphBar",
            systemImage: "sparkles",
            severity: .normal,
            tooltip: "GlyphBar"
        )
    }

    private func sortSignals(_ lhs: StatusSignal, _ rhs: StatusSignal) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.title < rhs.title
        }

        return lhs.priority > rhs.priority
    }
}
