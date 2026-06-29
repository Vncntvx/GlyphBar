import Foundation

/// Handles module upgrades: stops the old instance, migrates data, starts the new one.
@MainActor
final class ModuleUpgrader {
    private let logger: GlyphLogger

    init(logger: GlyphLogger = GlyphLogger()) {
        self.logger = logger
    }

    /// Perform an upgrade for a module instance.
    func upgrade(
        instanceID: ModuleInstanceID,
        from oldVersion: String,
        to newVersion: String,
        supervisor: ModuleSupervisor,
        migrate: (@MainActor (ModuleInstanceID, Int, Int) -> Void)? = nil
    ) async {
        logger.runtime("Upgrading \(instanceID.value) from \(oldVersion) to \(newVersion)")

        // Stop the old instance
        supervisor.cancelInFlight(for: instanceID.moduleID)

        // Run data migration if needed
        let fromMajor = versionMajor(oldVersion)
        let toMajor = versionMajor(newVersion)
        if fromMajor < toMajor {
            migrate?(instanceID, fromMajor, toMajor)
        }

        logger.runtime("Upgrade of \(instanceID.value) complete")
    }

    private func versionMajor(_ version: String) -> Int {
        let parts = version.split(separator: ".")
        return Int(parts.first ?? "1") ?? 1
    }
}
