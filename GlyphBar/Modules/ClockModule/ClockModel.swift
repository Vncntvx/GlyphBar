import Foundation

typealias ClockTimezoneOption = (id: String, label: String)

struct ClockState: Codable {
    let uses24HourClock: Bool
    let showSeconds: Bool
    let worldTimezones: [String]
}

enum ClockTimezoneCatalog {
    static let availableTimezones: [ClockTimezoneOption] = [
        ("Asia/Shanghai", "Beijing"),
        ("Asia/Tokyo", "Tokyo"),
        ("Europe/London", "London"),
        ("America/New_York", "New York"),
        ("America/Los_Angeles", "Los Angeles"),
        ("Europe/Berlin", "Berlin"),
        ("Asia/Dubai", "Dubai"),
        ("Pacific/Auckland", "Auckland"),
    ]

    static func isAvailable(_ id: String) -> Bool {
        availableTimezones.contains { $0.id == id }
    }

    static func label(for id: String) -> String {
        availableTimezones.first { $0.id == id }?.label ?? id
    }
}
