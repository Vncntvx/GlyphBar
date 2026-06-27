import SwiftUI

struct LogsView: View {
    let logger: GlyphLogger

    @State private var entries: [LogEntry] = []
    @State private var enabledCategories: Set<String> = ["general", "runtime", "routing", "statusItem"]
    @State private var searchText: String = ""

    private var filtered: [LogEntry] {
        entries
            .filter { enabledCategories.contains($0.category) }
            .filter { searchText.isEmpty || $0.message.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(["general", "runtime", "routing", "statusItem"], id: \.self) { category in
                    Toggle(category.capitalized, isOn: categoryBinding(category))
                        .toggleStyle(.checkbox)
                }
                Spacer()
                TextField("Search", text: $searchText).frame(width: 180)
                Button("Refresh") { reload() }
            }
            .padding(10)
            Divider()
            List {
                ForEach(filtered.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(entry.date, style: .time).font(.caption.monospaced())
                            Text(entry.category).font(.caption).foregroundStyle(.secondary)
                            Text(entry.level).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.message).font(.callout).textSelection(.enabled)
                    }
                }
            }
        }
        .frame(width: 720, height: 480)
        .onAppear { reload() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in reload() }
    }

    private func reload() {
        entries = logger.recentEntries()
    }

    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { enabledCategories.contains(category) },
            set: { if $0 { enabledCategories.insert(category) } else { enabledCategories.remove(category) } }
        )
    }
}
