import Foundation

enum Severity: String, Codable, CaseIterable, Comparable, Sendable {
    case normal
    case info
    case warning
    case critical

    var rank: Int {
        switch self {
        case .normal: return 0
        case .info: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}
