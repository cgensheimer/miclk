import AppKit

final class StatusBarController {

    var loginItemManager: LoginItemManager?
    var onOverlayToggled: ((Bool) -> Void)?

    private let statusItem: NSStatusItem
    private var isMuted = true
    private var isInverted = false
    private var overlayEnabled = true

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "miclk") {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "miclk"
        }
    }

    func update(muted: Bool, inverted: Bool) {
        isMuted = muted
        isInverted = inverted
        buildMenu()
    }

    func buildMenu() {
        let menu = NSMenu()

        let overlayItem = NSMenuItem(title: "show overlay", action: #selector(toggleOverlay), keyEquivalent: "")
        overlayItem.target = self
        overlayItem.state = overlayEnabled ? .on : .off
        menu.addItem(overlayItem)

        let launchItem = NSMenuItem(title: "launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        if let lim = loginItemManager {
            launchItem.state = lim.isEnabled ? .on : .off
        }
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let micText = isMuted ? "muted" : "unmuted"
        let micItem = NSMenuItem(title: "\(micText)  ·  capslk", action: nil, keyEquivalent: "")
        micItem.isEnabled = false
        menu.addItem(micItem)

        let defaultText = isInverted ? "default on" : "default off"
        let defaultItem = NSMenuItem(title: "\(defaultText)  ·  ⇧ + capslk", action: nil, keyEquivalent: "")
        defaultItem.isEnabled = false
        menu.addItem(defaultItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "quit miclk", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleOverlay() {
        overlayEnabled.toggle()
        onOverlayToggled?(overlayEnabled)
        buildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        guard let lim = loginItemManager else { return }
        if lim.isEnabled {
            lim.disable()
        } else {
            lim.enable()
        }
        buildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
