import Foundation

extension ModuleRuntime {
    func scheduleLocal(_ command: Command, for moduleID: ModuleID, after delay: TimeInterval) {
        let handle = localTaskClock.schedule(after: delay) { [weak self] in
            guard let self,
                  self.modules[moduleID] != nil,
                  self.settingsStore.isEnabled(moduleID)
            else { return }
            self.supervisor.dispatch(command, for: moduleID)
        }
        scheduledLocalHandles[moduleID, default: []].append(handle)
    }

    func cancelScheduledLocalTasks(for moduleID: ModuleID) {
        scheduledLocalHandles[moduleID]?.forEach { localTaskClock.cancel($0) }
        scheduledLocalHandles[moduleID] = nil
    }
}
