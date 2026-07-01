import Foundation

/// Per-module serial command processor. Each active module gets one
/// `ModuleActor` which ensures:
/// - Commands are processed one at a time (serial queue).
/// - Duplicate `.refresh` commands are coalesced (keep latest reason).
/// - User actions are never coalesced.
/// - Stale in-flight results are dropped when the generation advances.
///
/// P2 uses `@MainActor` (locked decision: no real actor isolation yet).
@MainActor
final class ModuleActor {
    let instanceID: ModuleID
    private(set) var operationalState: ModuleOperationalState
    private(set) var generation: GenerationToken
    private let scope: CancellationScope
    private var commandQueue: [PendingCommand] = []

    /// Handler called when the actor needs to execute a command against
    /// the actual module. The actor awaits the result, checks generation,
    /// and applies the state transition.
    var onExecute: ((ModuleID, Command, GenerationToken) async -> DomainTransition)?

    /// Handler called when the actor's operational state changes.
    var onStateChange: ((ModuleID, ModuleOperationalState) -> Void)?

    init(instanceID: ModuleID) {
        self.instanceID = instanceID
        self.operationalState = .idle
        self.generation = .initial
        self.scope = CancellationScope()
    }

    /// Enqueue a command for serial processing. Refresh commands are
    /// coalesced: if a `.refresh` is already queued, only the latest
    /// reason is kept.
    func enqueue(_ command: Command) {
        enqueue(PendingCommand(command: command, continuation: nil))
    }

    /// Enqueue a command and wait until the module has handled it.
    func perform(_ command: Command) async -> DomainTransition {
        await withCheckedContinuation { continuation in
            enqueue(PendingCommand(command: command, continuation: continuation))
        }
    }

    private func enqueue(_ pending: PendingCommand) {
        switch pending.command {
        case .refresh(let newReason):
            // Coalesce fire-and-forget refreshes only. Awaited commands keep
            // their continuation so tests and callers can observe completion.
            if pending.continuation == nil,
               let existingIndex = commandQueue.firstIndex(where: { queued in
                   if case .refresh = queued.command {
                       return queued.continuation == nil
                   }
                   return false
               }) {
                commandQueue[existingIndex] = PendingCommand(
                    command: .refresh(reason: newReason),
                    continuation: nil
                )
            } else {
                commandQueue.append(pending)
            }
        default:
            // User actions and other commands are never coalesced
            commandQueue.append(pending)
        }

        // If not currently processing, start the drain loop
        drainIfNeeded()
    }

    /// Cancel any in-flight work and bump the generation so results
    /// from the old task are discarded.
    func cancelInFlight() {
        scope.cancel()
        let pending = commandQueue
        commandQueue.removeAll()
        for command in pending {
            command.continuation?.resume(returning: .empty)
        }
        operationalState = .idle
    }

    /// Force a state transition (e.g. from Supervisor).
    func forceState(_ newState: ModuleOperationalState) {
        operationalState = newState
        onStateChange?(instanceID, operationalState)
    }

    // MARK: - Private

    private var isDraining = false

    private func drainIfNeeded() {
        guard !isDraining else { return }
        isDraining = true

        Task {
            await drainQueue()
            isDraining = false
            // Check if more commands arrived while we were draining
            if !commandQueue.isEmpty {
                drainIfNeeded()
            }
        }
    }

    private func drainQueue() async {
        while !commandQueue.isEmpty {
            let pending = commandQueue.removeFirst()
            let command = pending.command

            // Skip refreshes if we can't currently refresh
            if case .refresh = command, !operationalState.canRefresh {
                pending.continuation?.resume(returning: .empty)
                continue
            }

            let transition = await executeCommand(command)
            pending.continuation?.resume(returning: transition)
        }
    }

    private func executeCommand(_ command: Command) async -> DomainTransition {
        let token = scope.generation

        switch command {
        case .refresh:
            operationalState = operationalState.apply(.refreshBegan)
            onStateChange?(instanceID, operationalState)
        default:
            break
        }

        guard let onExecute else { return .empty }

        let transition = await onExecute(instanceID, command, token)

        // Generation check: discard stale results
        guard scope.isCurrent(token) else { return .empty }

        // Apply state transition based on result
        switch command {
        case .refresh:
            let hasError = transition.effects.contains { effect in
                if case .showNotice = effect { return true }
                return false
            }
            if hasError || transition.health?.isUnhealthy == true {
                let terminal = transition.health?.isTerminal ?? false
                operationalState = operationalState.apply(.refreshFailed(terminal: terminal))
            } else {
                operationalState = operationalState.apply(.refreshSucceeded)
            }
        default:
            break
        }

        onStateChange?(instanceID, operationalState)
        return transition
    }

    private struct PendingCommand {
        var command: Command
        var continuation: CheckedContinuation<DomainTransition, Never>?
    }
}
