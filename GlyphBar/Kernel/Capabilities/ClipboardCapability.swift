import AppKit
import Foundation

/// Clipboard capability. Replaces direct `NSPasteboard` usage inside modules.
@MainActor
final class ClipboardCapability: Capability {
    static let declaredKey: CapabilityKey = .clipboard

    func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func write(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
