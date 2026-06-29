import Foundation

/// Monotonically increasing token used to invalidate stale in-flight work.
/// When a module's generation is bumped (e.g. on disable/re-enable), any
/// Task still running with the old generation must not publish its result.
struct GenerationToken: Sendable, Equatable, Hashable, Comparable {
    let value: UInt64

    static let initial = GenerationToken(value: 1)

    func next() -> GenerationToken {
        GenerationToken(value: value + 1)
    }

    static func < (lhs: GenerationToken, rhs: GenerationToken) -> Bool {
        lhs.value < rhs.value
    }
}
