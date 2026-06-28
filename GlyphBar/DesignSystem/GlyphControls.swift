import SwiftUI

struct GlyphStatusBadge: View {
    var severity: Severity
    var title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var icon: String {
        switch severity {
        case .normal: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    private var color: Color {
        switch severity {
        case .normal: return .green
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct GlyphModuleHeader: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var severity: Severity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            GlyphStatusBadge(severity: severity, title: severity == .normal ? "Ready" : severity.rawValue.capitalized)
        }
    }
}

struct GlyphActionButton: View {
    var title: String
    var systemImage: String
    var role: ModuleAction.Role = .standard
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var tint: Color? {
        switch role {
        case .standard, .refresh:
            return nil
        case .destructive:
            return .red
        }
    }
}

struct GlyphToolbarButton: View {
    var systemImage: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .imageScale(.medium)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct GlyphSidebarItem: View {
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
