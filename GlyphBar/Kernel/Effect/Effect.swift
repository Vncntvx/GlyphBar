import Foundation

/// Effects are the kernel's unified output vocabulary.
enum Effect: Sendable {
    case publishSnapshot(SnapshotEnvelope)
    case persistDomainState(Data)
    case copyToClipboard(String)
    case openURL(URL)
    case showNotice(String)
    case openModuleSettings
    case requestFileImport(FileImportRequest)
    case requestRefresh(reason: Command.RefreshReason)
    case scheduleLocal(Command, after: TimeInterval)
}

/// A request for the runtime to present a file chooser to the user.
/// The runtime opens an NSOpenPanel, then delivers the result back to
/// the module via `Command.externalEvent(.fileImportCompleted/Cancelled)`.
struct FileImportRequest: Sendable {
    let requestID: UUID
    let allowedTypes: [String]
    let allowDirectories: Bool

    init(
        requestID: UUID = UUID(),
        allowedTypes: [String],
        allowDirectories: Bool = false
    ) {
        self.requestID = requestID
        self.allowedTypes = allowedTypes
        self.allowDirectories = allowDirectories
    }
}

struct NetworkRequest: Sendable {
    var url: URL
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: Data?
}
