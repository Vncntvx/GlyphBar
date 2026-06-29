import Foundation

/// One candidate for the status bar slot, produced by a module. The arbiter
/// (P1.6) picks a winner from the candidate pool each tick.
struct StatusCandidate: Sendable, Identifiable {
    let id: String                 // deduplication key
    let sourceModule: String       // P1 uses ModuleID
    let semanticRole: SemanticRole
    let severity: Severity
    let priority: Int              // 0...1000
    let text: String
    let icon: String
    let createdAt: Date
    let expiresAt: Date?           // TTL
    let interruptPolicy: InterruptPolicy
    let trustLevel: TrustLevel     // P1 default .bundled

    enum SemanticRole: Sendable {
        case primary
        case alert
        case informational
        case rotation
    }

    enum InterruptPolicy: Sendable {
        case normal
        case preempt
        case persistent
    }
}
