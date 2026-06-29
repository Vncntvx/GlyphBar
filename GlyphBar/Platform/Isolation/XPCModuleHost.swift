import Foundation

/// Main-app-side host that manages XPC connections for isolated modules.
/// Creates NSXPCConnection instances, manages lifecycle, and implements
/// XPCModuleHostProtocol to handle capability requests from XPC processes.
@MainActor
final class XPCModuleHost: NSObject, XPCModuleHostProtocol {
    private var connections: [ModuleInstanceID: NSXPCConnection] = [:]
    private let logger: GlyphLogger
    private let capabilityBroker: CapabilityBroker

    init(logger: GlyphLogger = GlyphLogger(), capabilityBroker: CapabilityBroker) {
        self.logger = logger
        self.capabilityBroker = capabilityBroker
        super.init()
    }

    /// Load a module in an XPC process. Creates the connection and returns
    /// a proxy that implements ModuleContract.
    func loadModule(package: Package) throws -> XPCModuleProxy {
        let serviceIdentifier = package.id.value
        let connection = NSXPCConnection(serviceName: serviceIdentifier)
        connection.exportedInterface = NSXPCInterface(with: XPCModuleHostProtocol.self)
        connection.exportedObject = self

        let instanceID = ModuleInstanceID.default(for: ModuleTypeID(value: package.manifest.id))
        connections[instanceID] = connection

        let proxy = XPCModuleProxy(instanceID: instanceID, connection: connection)
        logger.runtime("XPCModuleHost: loaded \(package.id.value)")
        return proxy
    }

    /// Terminate an XPC module and close its connection.
    func terminate(_ proxy: XPCModuleProxy) async {
        await proxy.terminate()
        connections.removeValue(forKey: proxy.instanceID)
        proxy.connection.invalidate()
        logger.runtime("XPCModuleHost: terminated \(proxy.instanceID.value)")
    }

    // MARK: - XPCModuleHostProtocol

    /// Handle network requests from XPC process — check capability broker first.
    nonisolated func requestNetwork(_ reqData: Data, reply: @escaping (Data?, Error?) -> Void) {
        // P4: validate capability grant before executing
        // For now, return an error (capability checking requires MainActor)
        reply(nil, NSError(domain: "GlyphBar.XPC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network capability not verified"]))
    }

    /// Handle secret requests from XPC process.
    nonisolated func requestSecret(_ key: String, reply: @escaping (String?) -> Void) {
        // P4: validate capability grant before returning secrets
        reply(nil)
    }

    /// Handle effect submissions from XPC process.
    nonisolated func submitEffects(_ effectsData: Data) {
        // P4: decode effects and route to EffectExecutor
        // For now, log that effects were received
    }
}
