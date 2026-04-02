import ServiceManagement

final class LoginItemManager {

    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        service.status == .enabled
    }

    func enable() {
        do {
            try service.register()
        } catch {
            print("miclk: failed to register login item: \(error)")
        }
    }

    func disable() {
        do {
            try service.unregister()
        } catch {
            print("miclk: failed to unregister login item: \(error)")
        }
    }
}
