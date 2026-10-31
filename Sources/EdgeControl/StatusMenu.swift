import AppKit

@MainActor
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let status = NSMenuItem(title: "Starting", action: nil, keyEquivalent: "")
    private let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
    private let permission = NSMenuItem(title: "Allow Accessibility…", action: nil, keyEquivalent: "")
    private let onToggle: () -> Void
    private let onPermission: () -> Void
    init(onToggle: @escaping () -> Void, onPermission: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onPermission = onPermission
        super.init()
        let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "EdgeControl")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "EdgeControl"
        let menu = NSMenu()
        menu.autoenablesItems = false
        status.isEnabled = false
        menu.addItem(status)
        permission.target = self
        permission.action = #selector(requestPermission)
        menu.addItem(permission)
        menu.addItem(.separator())
        pause.target = self
        pause.action = #selector(togglePause)
        menu.addItem(pause)
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }
    func update(_ title: String, paused: Bool) {
        status.title = title
        pause.title = paused ? "Resume" : "Pause"
        permission.isHidden = CursorCapture.hasPermission
    }
    func remove() { NSStatusBar.system.removeStatusItem(item) }
    @objc private func requestPermission() { onPermission() }
    @objc private func togglePause() { onToggle() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
