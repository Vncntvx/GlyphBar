import Foundation

/// Current schema versions for each protocol. P3 introduces per-protocol
/// versioning; all start at 1.
struct ProtocolVersions: Sendable {
    let packageSchema: Int
    let manifestSchema: Int
    let snapshotSchema: Int
    let projectionSchema: Int
    let storageSchema: Int
    let widgetBridgeSchema: Int
    let commandProtocol: Int
    let effectProtocol: Int
    let declarativeUISchema: Int

    static let current = ProtocolVersions(
        packageSchema: 1,
        manifestSchema: 1,
        snapshotSchema: 1,
        projectionSchema: 1,
        storageSchema: 1,
        widgetBridgeSchema: 1,
        commandProtocol: 1,
        effectProtocol: 1,
        declarativeUISchema: 1
    )
}

/// Protocol identifiers for schema versioning.
enum SchemaProtocol: String, CaseIterable, Sendable {
    case package
    case manifest
    case snapshot
    case projection
    case moduleStorage
    case widgetBridge
    case command
    case effect
    case declarativeUI
}

/// Policy for handling schema version mismatches.
struct SchemaVersionPolicy: Sendable {
    let supportedVersions: ClosedRange<Int>
    let unknownFieldStrategy: UnknownFieldStrategy
    let downgradeStrategy: DowngradeStrategy
    let snapshotStrategy: SnapshotDiscardStrategy
    let domainDataStrategy: DomainDataMigrationStrategy

    static let `default` = SchemaVersionPolicy(
        supportedVersions: 1...1,
        unknownFieldStrategy: .preserve,
        downgradeStrategy: .reject,
        snapshotStrategy: .discardAndRebuild,
        domainDataStrategy: .runMigrationChain
    )
}

enum UnknownFieldStrategy: Sendable {
    case preserve    // Keep unknown fields for forward compatibility
    case drop        // Drop unknown fields (strict)
}

enum DowngradeStrategy: Sendable {
    case reject      // Reject downgrades outright
    case bestEffort  // Try to load with potential data loss
}

enum SnapshotDiscardStrategy: Sendable {
    case discardAndRebuild  // Discard old snapshots, rebuild from refresh
    case preserveAsStale    // Mark as stale but keep
}

enum DomainDataMigrationStrategy: Sendable {
    case runMigrationChain   // Run StorageMigration chain
    case preserve            // Keep as-is (risky)
}
