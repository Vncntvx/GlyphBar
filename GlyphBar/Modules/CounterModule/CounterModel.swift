import Foundation

struct CounterState: Codable {
    let count: Int
    let stepSize: Int
    let minValue: Int?
    let maxValue: Int?
    let lastModified: Date?
}

struct CounterBounds: Codable {
    var minValue: Int?
    var maxValue: Int?
}
