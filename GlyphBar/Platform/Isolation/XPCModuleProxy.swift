import Foundation

/// Main-app-side proxy that implements ModuleContract for XPC-hosted modules.
/// Commands are serialized and sent over NSXPCConnection; DomainTransition
/// and Effects are received back.
@MainActor
final class XPCModuleProxy {
    let instanceID: ModuleInstanceID
    let connection: NSXPCConnection
    private let remote: XPCModuleProtocol

    init(instanceID: ModuleInstanceID, connection: NSXPCConnection) {
        self.instanceID = instanceID
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: XPCModuleProtocol.self)
        self.remote = connection.remoteObjectProxy as! XPCModuleProtocol
        connection.resume()
    }

    /// Send a command to the XPC module and await the response.
    func handle(commandData: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            remote.handle(commandData: commandData) { responseData in
                continuation.resume(returning: responseData)
            }
        }
    }

    /// Terminate the XPC module.
    func terminate() async {
        await withCheckedContinuation { continuation in
            remote.terminate { continuation.resume() }
        }
    }
}
