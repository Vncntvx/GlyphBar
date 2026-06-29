import AppKit
import Foundation
import UniformTypeIdentifiers

/// File-import capability. Replaces direct `NSOpenPanel` usage inside modules.
@MainActor
final class FileImportCapability: Capability {
    static let declaredKey: CapabilityKey = .fileImport

    private let moduleID: String

    init(moduleID: String) {
        self.moduleID = moduleID
    }

    /// Presents an open panel on the main actor and returns the chosen URL, or
    /// `nil` if the user cancels. P1 runs on the main actor — P2 may move this
    /// to a dedicated presentation coordinator.
    func requestImport(allowedTypes: [String]) async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.begin { response in
                    if response == .OK {
                        continuation.resume(returning: panel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
