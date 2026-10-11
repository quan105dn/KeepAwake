import Foundation
import ServiceManagement

/// Bật / tắt "Khởi động cùng macOS" qua SMAppService (macOS 13+).
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var error: String?

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ on: Bool) {
        error = nil
        do {
            if on {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}
