import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var audioManager: AudioManager!
    private var eventTapManager: EventTapManager!
    private var loginItemManager: LoginItemManager!
    private var overlayController: OverlayController!

    private var isInverted = false
    private var overlayEnabled = true
    private var eventTapRunning = false
    private var permissionTimer: Timer?

    private let activeDot = NSColor.systemRed
    private let mutedDot = NSColor(white: 1, alpha: 0.45)

    func applicationDidFinishLaunching(_ notification: Notification) {
        audioManager = AudioManager()
        statusBarController = StatusBarController()
        loginItemManager = LoginItemManager()
        overlayController = OverlayController()

        statusBarController.loginItemManager = loginItemManager
        statusBarController.onOverlayToggled = { [weak self] enabled in
            guard let self else { return }
            self.overlayEnabled = enabled
            if !enabled {
                self.overlayController.dismiss()
            } else {
                self.updateOverlay(muted: self.audioManager.isMuted())
            }
        }

        audioManager.setMute(true)
        syncMenu()

        audioManager.onMuteChanged = { [weak self] muted in
            DispatchQueue.main.async {
                self?.updateOverlay(muted: muted)
                self?.syncMenu()
            }
        }
        audioManager.onDefaultDeviceChanged = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                let muted = self.audioManager.isMuted()
                self.updateOverlay(muted: muted)
                self.syncMenu()
            }
        }
        audioManager.startListening()

        setupEventTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        eventTapManager?.stop()
        audioManager?.stopListening()
    }

    private func setupEventTap() {
        eventTapManager = EventTapManager()
        eventTapManager.onCapsLockChanged = { [weak self] capsLockOn, shiftHeld in
            self?.handleCapsLock(capsLockOn: capsLockOn, shiftHeld: shiftHeld)
        }

        if eventTapManager.start() {
            eventTapRunning = true
            return
        }

        CGRequestPostEventAccess()
        waitForPermission()
    }

    private func waitForPermission() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(accessibilityChanged),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tryActivateEventTap()
        }
    }

    @objc private func accessibilityChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.tryActivateEventTap()
        }
    }

    private func tryActivateEventTap() {
        guard !eventTapRunning else { return }

        if eventTapManager.start() {
            eventTapRunning = true
            stopWaiting()
            if overlayEnabled {
                overlayController.flash(text: "capslk ready", duration: 1.5)
            }
        } else if CGPreflightPostEventAccess() {
            stopWaiting()
            showRelaunchAlert()
        }
    }

    private func stopWaiting() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
    }

    private func showRelaunchAlert() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "permission was granted but miclk needs to restart."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    private func relaunch() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func syncMenu() {
        statusBarController.update(muted: audioManager.isMuted(), inverted: isInverted)
    }

    private func handleCapsLock(capsLockOn: Bool, shiftHeld: Bool) {
        if shiftHeld {
            isInverted.toggle()
        }

        let muted = isInverted ? capsLockOn : !capsLockOn
        audioManager.setMute(muted)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncMenu()

            if shiftHeld {
                let modeText = self.isInverted ? "default on" : "default off"
                if self.overlayEnabled {
                    self.overlayController.flash(text: modeText, duration: 1.5) { [weak self] in
                        guard let self else { return }
                        self.updateOverlay(muted: self.audioManager.isMuted())
                    }
                }
            } else {
                self.updateOverlay(muted: muted)
            }
        }
    }

    private func updateOverlay(muted: Bool) {
        guard overlayEnabled else { return }

        let isDefaultState = (muted != isInverted)

        if muted {
            if isDefaultState {
                overlayController.flash(text: "muted", dotColor: mutedDot, duration: 1.5)
            } else {
                overlayController.show(text: "muted", dotColor: mutedDot, pulsing: false)
            }
        } else {
            if isDefaultState {
                overlayController.flash(text: "active", dotColor: activeDot, pulsing: true, duration: 1.5)
            } else {
                overlayController.show(text: "active", dotColor: activeDot, pulsing: true)
            }
        }
    }

}
