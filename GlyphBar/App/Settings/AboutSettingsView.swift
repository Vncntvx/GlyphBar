import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
            Text("GlyphBar").font(.title2.weight(.semibold))
            Text("Wenjie Xu")
            Text("wenjie.xu.cn@outlook.com").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
