import Foundation
import Observation

extension StatusItemController {
    // MARK: - Rendering (P1.14: arbiter + renderer)

    func observeRuntime() {
        withObservationTracking {
            _ = runtime.snapshots
            _ = settingsStore.primaryModuleID
            _ = settingsStore.enabledModuleIDs
            _ = settingsStore.statusRotationEnabled
            _ = settingsStore.statusRotationInterval
            _ = settingsStore.rotationModuleIDs
            _ = settingsStore.rotationItemIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleRuntimeChange()
                self?.observeRuntime()
            }
        }
    }

    func handleRuntimeChange() {
        submitCandidatesToArbiter()
        updateRotationTimer()
        scheduleRender()
    }

    func submitCandidatesToArbiter() {
        arbiter.submit(collectAllCandidates(), now: .now)
    }

    func updateRotationTimer() {
        presentationTicker.stop()
        guard settingsStore.statusRotationEnabled else { return }
        let interval = TimeInterval(settingsStore.statusRotationInterval)
        presentationTicker.start(interval: interval) { [weak self] in
            guard let self else { return }
            self.runPresentationTicks()
            _ = self.arbiter.tick(now: .now)
            self.renderer.render(self.arbiter.currentDecision)
        }
    }

    func runPresentationTicks() {
        for (id, module) in runtime.modules {
            guard let tickable = module as? any PresentationTickable else {
                continue
            }
            let projection = tickable.buildProjection()
            _ = tickable.presentationTick(trigger: .timerTick, projection: projection)

            let candidates = tickable.statusCandidates()
            guard !candidates.isEmpty else {
                continue
            }
            var allCandidates = collectAllCandidates()
            allCandidates.removeAll { $0.sourceModule == id }
            allCandidates.append(contentsOf: candidates)
            arbiter.submit(allCandidates, now: .now)
        }
    }

    func collectAllCandidates() -> [StatusCandidate] {
        var candidates: [StatusCandidate] = []
        let enabledSnapshots = runtime.snapshots.filter { settingsStore.isEnabled($0.key) }

        for (id, snapshot) in enabledSnapshots {
            if let module = runtime.modules[id] {
                candidates.append(contentsOf: module.statusCandidates())
            } else {
                let projection = ProjectionBuilder.build(from: snapshot)
                candidates.append(contentsOf: projection.statusCandidates)
            }
        }

        if !settingsStore.rotationModuleIDs.isEmpty {
            candidates = candidates.filter { candidate in
                if candidate.semanticRole == .rotation {
                    return settingsStore.rotationModuleIDs.contains(candidate.sourceModule)
                }
                return true
            }
        }

        return candidates
    }

    func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    func render() {
        renderer.render(arbiter.currentDecision)
    }
}
