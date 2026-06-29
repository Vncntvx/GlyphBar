import Foundation

/// The desired state of a module instance, as configured by the user or system.
/// The Reconciler compares `DesiredModuleState` against `ObservedModuleState`
/// and produces `ReconcileAction`s to converge.
struct DesiredModuleState: Codable, Sendable, Equatable {
    let instanceID: ModuleInstanceID
    let typeID: ModuleTypeID
    let packageID: PackageID
    var enabled: Bool
    var refreshPolicy: RefreshPolicy
    var grantedCapabilities: Set<CapabilityKey>
    var statusBarEnabled: Bool
    var widgetEnabled: Bool
    var priorityPolicy: PriorityPolicy
    var packageVersion: String
    var instanceConfig: [String: String]  // Multi-instance config (e.g. DeepSeek accounts)

    init(
        instanceID: ModuleInstanceID,
        typeID: ModuleTypeID,
        packageID: PackageID,
        enabled: Bool = true,
        refreshPolicy: RefreshPolicy = .manual,
        grantedCapabilities: Set<CapabilityKey> = [],
        statusBarEnabled: Bool = true,
        widgetEnabled: Bool = true,
        priorityPolicy: PriorityPolicy = PriorityPolicy(order: 0, trustLevel: .bundled),
        packageVersion: String = "1.0.0",
        instanceConfig: [String: String] = [:]
    ) {
        self.instanceID = instanceID
        self.typeID = typeID
        self.packageID = packageID
        self.enabled = enabled
        self.refreshPolicy = refreshPolicy
        self.grantedCapabilities = grantedCapabilities
        self.statusBarEnabled = statusBarEnabled
        self.widgetEnabled = widgetEnabled
        self.priorityPolicy = priorityPolicy
        self.packageVersion = packageVersion
        self.instanceConfig = instanceConfig
    }
}

struct PriorityPolicy: Codable, Sendable, Equatable {
    var order: Int
    var trustLevel: TrustLevel
}
