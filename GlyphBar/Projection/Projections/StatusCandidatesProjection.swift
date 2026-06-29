import Foundation

/// P1 placeholder. P1.6 fills in `StatusCandidate` and this projection just
/// wraps the candidate list. Real status-bar aggregation moves to
/// `PresentationArbiter` (P1.6/P1.14).
struct StatusCandidatesProjection: Sendable {
    let candidates: [StatusCandidate]
}
