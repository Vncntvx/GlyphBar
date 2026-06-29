import Foundation

/// Trust tier for a status candidate. Bundled modules get `.bundled`; signed
/// third-party modules get `.signed`; unsigned local modules get `.unsignedLocal`;
/// untrusted sources get `.untrusted`. The arbiter uses this to break ties and
/// to prevent untrusted candidates from starving bundled ones.
enum TrustLevel: Sendable, Comparable, Codable {
    case untrusted
    case unsignedLocal
    case bundled
    case signed

    var rank: Int {
        switch self {
        case .untrusted: return 0
        case .unsignedLocal: return 1
        case .bundled: return 2
        case .signed: return 3
        }
    }

    static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}
