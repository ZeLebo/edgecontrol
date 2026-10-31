import AppKit

@MainActor
final class LevelHUD {
    private let panel: HUDPanel
    private let content = LevelView(frame: NSRect(x: 0, y: 0, width: 292, height: 92))
    private var hideTimer: Timer?

    init() {
        panel = HUDPanel(contentRect: content.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = content
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
    }

    func show(action: EdgeAction, percent: Int, diagnostic: Bool = false) {
        guard action != .disabled, (0...100).contains(percent) else { return }
        hideTimer?.invalidate()
        hideTimer = nil
        content.configure(action: action, percent: percent, diagnostic: diagnostic)
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 72))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func finish() {
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 0.7, target: self, selector: #selector(hideAfterGesture), userInfo: nil, repeats: false)
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    @objc private func hideAfterGesture() {
        hideTimer = nil
        // Immediate hiding also avoids stale animation completions hiding a new gesture.
        hide()
    }

    func renderPreview(to url: URL, action: EdgeAction = .volume, appearance: NSAppearance.Name = .aqua) throws {
        panel.appearance = NSAppearance(named: appearance)
        content.appearance = panel.appearance
        content.configure(action: action, percent: 64, diagnostic: false)
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw HUDPreviewError()
        }
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.cacheDisplay(in: content.bounds, to: bitmap)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw HUDPreviewError() }
        try data.write(to: url)
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class LevelView: NSView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "Volume")
    private let value = NSTextField(labelWithString: "64%")
    private let bar = NSProgressIndicator()
    private var accent = NSColor.systemBlue

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.frame = NSRect(x: 22, y: 41, width: 28, height: 28)
        icon.imageScaling = .scaleProportionallyDown
        title.frame = NSRect(x: 62, y: 44, width: 145, height: 22)
        title.font = .systemFont(ofSize: 15, weight: .medium)
        value.frame = NSRect(x: 205, y: 41, width: 65, height: 26)
        value.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        value.alignment = .right
        bar.frame = NSRect(x: 22, y: 22, width: 248, height: 8)
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        for view in [icon, title, value, bar] { addSubview(view) }
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { nil }

    func configure(action: EdgeAction, percent: Int, diagnostic: Bool) {
        accent = action == .brightness ? .systemOrange : .systemBlue
        let image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)
        icon.image = image?.withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
        icon.contentTintColor = accent
        title.stringValue = diagnostic ? "Diagnostic: \(action.title.lowercased())" : action.title
        title.font = .systemFont(ofSize: diagnostic ? 12 : 15, weight: .medium)
        value.stringValue = "\(percent)%"
        bar.doubleValue = Double(percent)
        setAccessibilityLabel("\(title.stringValue), \(percent) percent")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 20, yRadius: 20).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 20, yRadius: 20).stroke()
    }
}

private struct HUDPreviewError: LocalizedError {
    var errorDescription: String? { "Could not save the level preview" }
}
