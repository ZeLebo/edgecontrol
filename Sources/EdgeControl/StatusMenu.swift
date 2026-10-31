import AppKit

@MainActor
final class StatusMenu: NSObject {
    private let statusItem: NSStatusItem
    private let stateItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Accessibility…", action: nil, keyEquivalent: "")
    private let onTogglePause: () -> Void
    private let onQuit: () -> Void
    private let onRequestPermission: () -> Void

    init(
        onTogglePause: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onRequestPermission: @escaping () -> Void
    ) {
        self.onTogglePause = onTogglePause
        self.onQuit = onQuit
        self.onRequestPermission = onRequestPermission
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 3, y: 3, width: 16, height: 12), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.3
            outline.stroke()
            let edges = NSBezierPath()
            edges.lineWidth = 2.3
            edges.lineCapStyle = .round
            edges.move(to: NSPoint(x: 7, y: 3))
            edges.line(to: NSPoint(x: 15, y: 3))
            edges.move(to: NSPoint(x: 19, y: 7))
            edges.line(to: NSPoint(x: 19, y: 11))
            edges.stroke()
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "EdgeControl"
        statusItem.button?.setAccessibilityLabel("EdgeControl")

        let menu = NSMenu()
        menu.autoenablesItems = false
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        permissionItem.target = self
        permissionItem.action = #selector(requestPermission)
        permissionItem.isHidden = true
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        pauseItem.target = self
        pauseItem.action = #selector(togglePause)
        menu.addItem(pauseItem)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func update(status: String, isPaused: Bool, needsPermission: Bool) {
        stateItem.title = status
        pauseItem.title = isPaused ? "Resume" : "Pause"
        permissionItem.isHidden = !needsPermission
        statusItem.button?.toolTip = "EdgeControl: \(status)"
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePause() { onTogglePause() }
    @objc private func quit() { onQuit() }
    @objc private func requestPermission() { onRequestPermission() }
}
