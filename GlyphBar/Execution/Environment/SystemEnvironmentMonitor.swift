import Foundation

/// Monitors system environment changes (power, network, app activity, sleep/wake)
/// and notifies subscribers. The scheduler uses these signals to scale refresh
/// intervals and trigger batch recovery after sleep/wake.
@MainActor
final class SystemEnvironmentMonitor {
    var isAppVisible = true
    var isOnBattery = false
    var isNetworkReachable = true
    var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var subscribers: [@Sendable (SystemEvent) -> Void] = []

    func subscribe(_ handler: @escaping @Sendable (SystemEvent) -> Void) {
        subscribers.append(handler)
    }

    func notify(_ event: SystemEvent) {
        switch event {
        case .appBecameActive:
            isAppVisible = true
        case .appResignedActive:
            isAppVisible = false
        case .systemWake:
            isAppVisible = true
        case .systemSleep:
            isAppVisible = false
        case .networkChanged(let reachable):
            isNetworkReachable = reachable
        case .powerStateChanged(let onBattery, let lowPower):
            isOnBattery = onBattery
            isLowPower = lowPower
        }

        for handler in subscribers {
            handler(event)
        }
    }
}

enum SystemEvent: Sendable {
    case appBecameActive
    case appResignedActive
    case systemWake
    case systemSleep
    case networkChanged(reachable: Bool)
    case powerStateChanged(onBattery: Bool, lowPower: Bool)
}
