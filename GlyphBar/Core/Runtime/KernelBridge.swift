import Foundation

@MainActor
final class KernelBridge: ModuleBridge {
    private let handler: ([Effect]) -> Void

    init(handler: @escaping ([Effect]) -> Void) {
        self.handler = handler
    }

    func submit(_ effects: [Effect]) {
        handler(effects)
    }

    func submit(_ effect: Effect) {
        submit([effect])
    }
}
