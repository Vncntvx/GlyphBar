import Foundation

/// Protocol for storage migrations between schema versions.
protocol StorageMigration: Sendable {
    associatedtype State: Codable
    static var fromVersion: Int { get }
    static var toVersion: Int { get }
    static func migrate(_ from: State) -> State
}
