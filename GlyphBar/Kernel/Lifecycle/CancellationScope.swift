import Foundation

/// Manages a single in-flight task with generation tracking. When the
/// generation is bumped (e.g. on cancel/re-schedule), the old task's
/// result is silently dropped.
@MainActor
final class CancellationScope {
    private(set) var generation: GenerationToken
    private var task: Task<Void, Never>?

    init(generation: GenerationToken = .initial) {
        self.generation = generation
    }

    /// Replace the current task with a new one, bumping the generation.
    /// The old task is cancelled and its result will be discarded.
    func replace(with newTask: Task<Void, Never>) {
        task?.cancel()
        generation = generation.next()
        task = newTask
    }

    /// Cancel the current task and bump generation.
    func cancel() {
        task?.cancel()
        generation = generation.next()
        task = nil
    }

    /// Check if the current generation matches — used to decide whether
    /// to accept or discard a task's result.
    func isCurrent(_ token: GenerationToken) -> Bool {
        token == generation
    }
}
