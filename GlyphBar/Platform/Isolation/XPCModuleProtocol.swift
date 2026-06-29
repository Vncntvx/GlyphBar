import Foundation

/// XPC over-the-wire protocol for module communication. Both the main app
/// and the XPC service must implement relevant sides of this protocol.
///
/// P4 delivers the protocol and host-side proxy; the actual XPC service
/// target (`GlyphBarXPCModule.xpc`) would be a separate Xcode target.
@objc protocol XPCModuleProtocol {
    func load(manifestData: Data, reply: @escaping (Error?) -> Void)
    func handle(commandData: Data, reply: @escaping (Data) -> Void)
    func terminate(reply: @escaping () -> Void)
}

/// Protocol for the XPC process to call back to the main app for capability
/// requests (network, secret store, etc.). All platform access from the
/// XPC process goes through this proxy — the XPC process has NO direct
/// access to clipboard, filesystem, UserDefaults, or Keychain.
@objc protocol XPCModuleHostProtocol {
    func requestNetwork(_ reqData: Data, reply: @escaping (Data?, Error?) -> Void)
    func requestSecret(_ key: String, reply: @escaping (String?) -> Void)
    func submitEffects(_ effectsData: Data)
}
