import Foundation

/// Effects are the kernel's unified output vocabulary.
enum Effect: Sendable {
    case publishSnapshot(SnapshotEnvelope)
    case persistDomainState(Data)
    case copyToClipboard(String)
    case openURL(URL)
    case showNotice(String)
    case openModuleSettings
    case requestFileImport(allowedTypes: [String])
    case requestRefresh(reason: Command.RefreshReason)
    case scheduleLocal(Command, after: TimeInterval)
    case networkRequest(NetworkRequest)
}

struct NetworkRequest: Sendable {
    var url: URL
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: Data?
}
