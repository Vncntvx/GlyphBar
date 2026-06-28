import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }
            Text("GlyphBar").font(.title2.weight(.semibold))
            Text("Developer: Wenjie Xu")
                .font(.body)
            Text("wenjie.xu.cn@outlook.com")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
