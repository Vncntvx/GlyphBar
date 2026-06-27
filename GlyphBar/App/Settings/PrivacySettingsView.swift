import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var permissionCenter: PermissionCenter

    init(environment: AppEnvironment) {
        self.environment = environment
        self._permissionCenter = ObservedObject(wrappedValue: environment.permissionCenter)
    }

    var body: some View {
        Form {
            Section {
                ForEach(ModulePermission.allCases, id: \.self) { permission in
                    Toggle(title(for: permission), isOn: binding(for: permission))
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Granted permissions allow modules to use these capabilities. Revoking may affect module behavior.")
            }
        }
        .formStyle(.grouped)
    }

    private func title(for permission: ModulePermission) -> String {
        switch permission {
        case .pasteboard: return "Pasteboard"
        case .notifications: return "Notifications"
        case .systemMetrics: return "System Metrics"
        case .appGroupStorage: return "App Group Storage"
        case .openExternalURLs: return "Open External URLs"
        case .localFiles: return "Local Files"
        }
    }

    private func binding(for permission: ModulePermission) -> Binding<Bool> {
        Binding(
            get: { permissionCenter.isGranted(permission) },
            set: { $0 ? permissionCenter.grant(permission) : permissionCenter.revoke(permission) }
        )
    }
}
