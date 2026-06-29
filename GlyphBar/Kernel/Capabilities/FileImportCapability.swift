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
    /// `nil` if the user cancels.
    func requestImport(allowedTypes: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
