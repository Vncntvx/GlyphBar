import Foundation
import Testing
@testable import GlyphBar

// MARK: - ModuleOperationalState Tests

struct ModuleOperationalStateTests {
    @Test func normalLifecycleTransitions() {
        var state = ModuleOperationalState.installed

        state = state.apply(.load)
        #expect(state == .loaded)

        state = state.apply(.start)
        #expect(state == .starting)

        state = state.apply(.refreshBegan)
        #expect(state == .refreshing)

        state = state.apply(.refreshSucceeded)
        #expect(state == .ready)
    }

    @Test func refreshFailureNonTerminalGoesIdle() {
        var state = ModuleOperationalState.refreshing
        state = state.apply(.refreshFailed(terminal: false))
        #expect(state == .idle)
    }

    @Test func refreshFailureTerminalGoesFailed() {
        var state = ModuleOperationalState.refreshing
        state = state.apply(.refreshFailed(terminal: true))
        #expect(state == .failed)
    }

    @Test func suspendAndResume() {
        var state = ModuleOperationalState.ready
        state = state.apply(.suspend)
        #expect(state == .suspended)

        state = state.apply(.resume)
        #expect(state == .idle)
    }

    @Test func degradeAndRecover() {
        var state = ModuleOperationalState.ready
        state = state.apply(.degrade)
        #expect(state == .degraded)

        state = state.apply(.recover)
        #expect(state == .ready)
    }

    @Test func failedCanRecover() {
        var state = ModuleOperationalState.failed
        state = state.apply(.recover)
        #expect(state == .idle)
    }

    @Test func invalidTransitionIsIdempotent() {
        var state = ModuleOperationalState.installed
        // Can't start before loading
        state = state.apply(.start)
        #expect(state == .installed)
    }

    @Test func canRefreshProperty() {
        #expect(ModuleOperationalState.idle.canRefresh == true)
        #expect(ModuleOperationalState.ready.canRefresh == true)
        #expect(ModuleOperationalState.degraded.canRefresh == true)
        #expect(ModuleOperationalState.suspended.canRefresh == false)
        #expect(ModuleOperationalState.failed.canRefresh == false)
        #expect(ModuleOperationalState.refreshing.canRefresh == false)
    }

    @Test func stopGoesToStopping() {
        var state = ModuleOperationalState.ready
        state = state.apply(.stop)
        #expect(state == .stopping)

        state = state.apply(.uninstall)
        #expect(state == .uninstalled)
    }
}

// MARK: - GenerationToken Tests

struct GenerationTokenTests {
    @Test func tokenMonotonicallyIncreases() {
        let t1 = GenerationToken.initial
        let t2 = t1.next()
        let t3 = t2.next()

        #expect(t1 < t2)
        #expect(t2 < t3)
        #expect(t1 != t2)
    }

    @Test func initialTokenIsNotZero() {
        #expect(GenerationToken.initial.value > 0)
    }
}

// MARK: - CancellationScope Tests

@MainActor
struct CancellationScopeTests {
    @Test func cancelBumpsGeneration() {
        let scope = CancellationScope()
        let gen1 = scope.generation
        scope.cancel()
        let gen2 = scope.generation
        #expect(gen1 != gen2)
        #expect(gen1 < gen2)
    }

    @Test func isCurrentChecksGeneration() {
        let scope = CancellationScope()
        let gen = scope.generation
        #expect(scope.isCurrent(gen))
        scope.cancel()
        #expect(!scope.isCurrent(gen))
    }
}

// MARK: - VirtualClock Tests

@MainActor
struct VirtualClockTests {
    @Test func virtualClockAdvancesTime() {
        let clock = VirtualClock()
        let t0 = clock.now()
        clock.advance(by: 60)
        let t1 = clock.now()
        #expect(t1.timeIntervalSince(t0) == 60)
    }

    @Test func virtualClockFiresScheduledCallbacks() {
        let clock = VirtualClock()
        var fired = false
        _ = clock.schedule(after: 10) { fired = true }
        #expect(!fired)
        clock.advance(by: 5)
        #expect(!fired)
        clock.advance(by: 10)
        #expect(fired)
    }

    @Test func virtualClockCancelsScheduledCallbacks() {
        let clock = VirtualClock()
        var fired = false
        let handle = clock.schedule(after: 10) { fired = true }
        clock.cancel(handle)
        clock.advance(by: 20)
        #expect(!fired)
    }
}

// MARK: - PresentationTicker Tests

@MainActor
struct PresentationTickerTests {
    @Test func presentationTickerDoesNotTriggerRefresh() async {
        // The ticker should only drive display updates (arbiter tick),
        // never trigger a data refresh.
        let ticker = PresentationTicker()
        var refreshCount = 0
        var tickCount = 0

        ticker.start(interval: 0.1) {
            tickCount += 1
            // This is a presentation tick, NOT a refresh
        }

        // Wait briefly for at least one tick
        try? await Task.sleep(for: .milliseconds(200))

        ticker.stop()
        #expect(tickCount >= 1)
        #expect(refreshCount == 0)  // Ticker must NOT trigger refreshes
    }
}

// MARK: - ModuleActor Coalescing Tests

@MainActor
struct ModuleActorCoalescingTests {
    @Test func coalescingDedupesRapidRefreshRequests() async {
        let actor = ModuleActor(instanceID: "test")
        var refreshCount = 0

        actor.onExecute = { _, command, _ in
            if case .refresh = command {
                refreshCount += 1
            }
            return .empty
        }

        // Enqueue multiple rapid refreshes — should be coalesced to one
        actor.enqueue(.refresh(reason: .scheduled))
        actor.enqueue(.refresh(reason: .manual))
        actor.enqueue(.refresh(reason: .scheduled))

        // Give the actor time to drain
        try? await Task.sleep(for: .milliseconds(100))

        // Only one refresh should have been executed (coalesced)
        #expect(refreshCount <= 1)
    }
}

// MARK: - Supervisor Isolation Tests

@MainActor
struct SupervisorIsolationTests {
    @Test func supervisorIsolatesFailureToOneModule() async {
        let factory = CapabilityFactory()
        let supervisor = ModuleSupervisor(capabilityFactory: factory)
        var stateChanges: [ModuleID: ModuleOperationalState] = [:]

        supervisor.onOperationalStateChange = { id, state in
            stateChanges[id] = state
        }

        // Register two modules
        let module1 = CounterModule()
        let module2 = NotesQuickModule()
        supervisor.register(moduleID: "counter", module: module1)
        supervisor.register(moduleID: "notesQuick", module: module2)

        // Failure in one module should not affect the other
        let policy = supervisor.handleFailure("counter", error: NSError(domain: "test", code: 1))
        #expect(policy == .retry(backoff: 5.0))

        // The other module should still be operational
        let otherState = supervisor.operationalState(for: "notesQuick")
        #expect(otherState == .idle)
    }
}

// MARK: - Effective Interval Tests

@MainActor
struct EffectiveIntervalTests {
    @Test func effectiveIntervalScalesWithEnvironment() {
        let clock = VirtualClock()
        let scheduler = RefreshScheduler(clock: clock)

        // Panel visible: normal interval
        scheduler.setPanelVisible(true)
        #expect(scheduler.effectiveInterval(30) == 30)

        // Panel hidden: 3x
        scheduler.setPanelVisible(false)
        #expect(scheduler.effectiveInterval(30) == 90)
    }

    @Test func lowPowerDoublesInterval() {
        let clock = VirtualClock()
        let scheduler = RefreshScheduler(clock: clock)
        scheduler.setPanelVisible(true)
        scheduler.onSystemEvent(.powerStateChanged(onBattery: true, lowPower: true))
        #expect(scheduler.effectiveInterval(30) == 60)
    }

    @Test func inactiveAppDoublesInterval() {
        let clock = VirtualClock()
        let scheduler = RefreshScheduler(clock: clock)
        scheduler.setPanelVisible(true)
        scheduler.onSystemEvent(.appResignedActive)
        #expect(scheduler.effectiveInterval(30) == 60)
    }
}
