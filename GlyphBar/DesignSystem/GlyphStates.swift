import SwiftUI

struct GlyphEmptyStateView: View {
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 38))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GlyphErrorView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        GlyphEmptyStateView(
            title: "Unavailable",
            subtitle: message,
            systemImage: "exclamationmark.octagon"
        )
        .overlay(alignment: .bottom) {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
        }
    }
}

struct GlyphLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Refreshing")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GlyphWidgetCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct GlyphWidgetMetricView: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
