import Foundation
import Observation

@MainActor
@Observable
final class PermissionCenter {
    private(set) var grantedPermissions: Set<ModulePermission>

    init(defaults: UserDefaults = .standard) {
        let rawValues = defaults.stringArray(forKey: "permissions.granted") ?? []
        grantedPermissions = Set(rawValues.compactMap(ModulePermission.init(rawValue:)))
        self.defaults = defaults
    }

    private let defaults: UserDefaults

    func grant(_ permission: ModulePermission) {
        grantedPermissions.insert(permission)
        persist()
    }

    func revoke(_ permission: ModulePermission) {
        grantedPermissions.remove(permission)
        persist()
    }

    func isGranted(_ permission: ModulePermission) -> Bool {
        grantedPermissions.contains(permission)
    }

    private func persist() {
        defaults.set(grantedPermissions.map(\.rawValue).sorted(), forKey: "permissions.granted")
    }
}
