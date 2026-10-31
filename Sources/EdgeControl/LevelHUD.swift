import AppKit

@MainActor
final class LevelHUD {
    private let panel: HUDPanel
    private let content = HUDContentView(frame: NSRect(x: 0, y: 0, width: 220, height: 52))
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
        guard action.isLevel, (0...100).contains(percent) else { return }
        prepare(width: 220)
        content.configure(action: action, percent: percent, diagnostic: diagnostic)
        present()
    }

    func showSymbol(_ symbol: String, accessibilityLabel: String) {
        prepare(width: 64)
        content.configure(symbol: symbol, accessibilityLabel: accessibilityLabel)
        present()
        finish()
    }

    private func prepare(width: CGFloat) {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.setContentSize(NSSize(width: width, height: 52))
        content.frame = NSRect(x: 0, y: 0, width: width, height: 52)
    }

    private func present() {
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 72))
        }
        panel.orderFrontRegardless()
        // Draw the latest target in this update, without a control's interpolation or animation.
        content.displayIfNeeded()
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
    }

    @objc private func hideAfterGesture() {
        hideTimer = nil
        hide()
    }

    func renderPreview(to url: URL, action: EdgeAction = .volume, appearance: NSAppearance.Name = .aqua) throws {
        panel.appearance = NSAppearance(named: appearance)
        content.appearance = panel.appearance
        if action.isLevel {
            prepare(width: 220)
            content.configure(action: action, percent: 64, diagnostic: false)
        } else {
            prepare(width: 64)
            content.configure(symbol: action.symbol, accessibilityLabel: action.title)
        }
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
private final class HUDContentView: NSView {
    private let icon = NSImageView()
    private let meter = HUDMeterView(frame: NSRect(x: 52, y: 22, width: 150, height: 8))
    private var symbol: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = .labelColor
        addSubview(icon)
        addSubview(meter)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { nil }

    func configure(action: EdgeAction, percent: Int, diagnostic: Bool) {
        icon.frame = NSRect(x: 17, y: 16, width: 20, height: 20)
        setSymbol(action.symbol)
        meter.isHidden = false
        meter.setLevel(percent)
        let prefix = diagnostic ? "Diagnostic target " : ""
        setAccessibilityLabel("\(prefix)\(action.title), \(percent) percent")
        needsDisplay = true
    }

    func configure(symbol: String, accessibilityLabel: String) {
        icon.frame = NSRect(x: (bounds.width - 24) / 2, y: 14, width: 24, height: 24)
        setSymbol(symbol)
        meter.isHidden = true
        setAccessibilityLabel(accessibilityLabel)
        needsDisplay = true
    }

    private func setSymbol(_ name: String) {
        guard symbol != name else { return }
        symbol = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        icon.image = image?.withSymbolConfiguration(.init(pointSize: 20, weight: .medium))
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        shape.fill()
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}

@MainActor
final class HUDMeterView: NSView {
    private(set) var percent = 0

    var filledRect: NSRect {
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width * CGFloat(percent) / 100, height: bounds.height)
    }

    func setLevel(_ percent: Int) {
        self.percent = percent
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let fill = filledRect
        if fill.width > 0 {
            NSColor.labelColor.withAlphaComponent(0.9).setFill()
            let radius = min(fill.width, fill.height) / 2
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }
    }
}

private struct HUDPreviewError: LocalizedError {
    var errorDescription: String? { "Unable to save the level indicator preview" }
}
