import Foundation

/// Bridge the kernel exposes to modules for submitting effects.
///
/// Modules call `bridge.submit(.copyToClipboard(...))` etc. instead of touching
/// `NSPasteboard`, `URLSession`, or `WidgetDataBridge` directly. The kernel's
/// `EffectExecutor` (P1.8) performs the actual side effect.
@MainActor
protocol ModuleBridge: AnyObject {
    func submit(_ effects: [Effect])
    func submit(_ effect: Effect)
}
