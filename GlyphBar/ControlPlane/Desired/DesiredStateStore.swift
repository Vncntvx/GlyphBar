import Foundation

/// Persisted desired state for all module instances. Backed by a JSON file
/// in Application Support for transactional writes.
@MainActor
final class DesiredStateStore {
    private var states: [ModuleInstanceID: DesiredModuleState] = [:]
    private let fileURL: URL
    private let logger: GlyphLogger

    init(logger: GlyphLogger = GlyphLogger()) {
        self.logger = logger
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appending(path: "GlyphBar", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appending(path: "desired-state.json")
        load()
    }

    /// Get the desired state for a module instance.
    func state(for instanceID: ModuleInstanceID) -> DesiredModuleState? {
        states[instanceID]
    }

    /// Set the desired state for a module instance.
    func setState(_ state: DesiredModuleState) {
        states[state.instanceID] = state
        save()
    }

    /// Remove the desired state for a module instance.
    func removeState(for instanceID: ModuleInstanceID) {
        states.removeValue(forKey: instanceID)
        save()
    }

    /// All desired states.
    var allStates: [ModuleInstanceID: DesiredModuleState] { states }

    /// All enabled instance IDs.
    var enabledInstanceIDs: [ModuleInstanceID] {
        states.filter { $0.value.enabled }.map(\.key)
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoded = try? JSONDecoder().decode([String: DesiredModuleState].self, from: data)
        if let decoded {
            states = Dictionary(uniqueKeysWithValues: decoded.map { (ModuleInstanceID(value: $0.key), $0.value) })
        }
    }

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: states.map { ($0.key.value, $0.value) })
        guard let data = try? JSONEncoder().encode(dict) else { return }
        // Transactional write: write directly to the file
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save desired state: \(error.localizedDescription)")
        }
    }
}
