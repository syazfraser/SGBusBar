import Observation
import ServiceManagement

/// Launch at login, through macOS's Login Items.
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    private(set) var error: String?

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    /// macOS can ask you to allow it in System Settings > General > Login Items first.
    var needsApproval: Bool { status == .requiresApproval }

    func set(_ on: Bool) {
        error = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
