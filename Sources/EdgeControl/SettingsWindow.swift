import AppKit

@MainActor
final class SettingsWindow: NSObject {
    private let store: SettingsStore
    private let window: NSWindow
    private let diagram = TrackpadDiagramView(frame: NSRect(x: 194, y: 212, width: 232, height: 148))
    private var selectors: [TrackpadEdge: NSPopUpButton] = [:]
    private let widthSlider = NSSlider(value: 5, minValue: 3, maxValue: 15, target: nil, action: nil)
    private let widthLabel = NSTextField(labelWithString: "5%")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(store: SettingsStore) {
        self.store = store
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "EdgeControl Settings"
        window.isReleasedWhenClosed = false
        window.center()
        buildContent()
        refreshControls()
    }

    func show() {
        refreshControls()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() { window.close() }

    func renderPreview(to url: URL, appearance: NSAppearance.Name = .aqua) throws {
        guard let content = window.contentView else { throw SettingsPreviewError.unavailable }
        window.appearance = NSAppearance(named: appearance)
        content.appearance = window.appearance
        content.layoutSubtreeIfNeeded()
        guard let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw SettingsPreviewError.unavailable
        }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.cacheDisplay(in: content.bounds, to: image)
        }
        guard let data = image.representation(using: .png, properties: [:]) else {
            throw SettingsPreviewError.unavailable
        }
        try data.write(to: url, options: .atomic)
    }

    private func buildContent() {
        let content = SettingsBackgroundView(frame: NSRect(x: 0, y: 0, width: 620, height: 520))
        window.contentView = content

        let title = NSTextField(labelWithString: "Trackpad Edges")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.frame = NSRect(x: 24, y: 472, width: 560, height: 32)
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Choose an action for each edge. Slide to set a level from 0 to 100%.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 447, width: 572, height: 20)
        content.addSubview(subtitle)
        content.addSubview(diagram)

        addSelector(.top, frame: NSRect(x: 220, y: 382, width: 180, height: 52), to: content)
        addSelector(.right, frame: NSRect(x: 436, y: 260, width: 160, height: 52), to: content)
        addSelector(.bottom, frame: NSRect(x: 220, y: 158, width: 180, height: 52), to: content)
        addSelector(.left, frame: NSRect(x: 24, y: 260, width: 160, height: 52), to: content)

        let widthTitle = NSTextField(labelWithString: "Edge Width")
        widthTitle.font = .systemFont(ofSize: 13, weight: .medium)
        widthTitle.frame = NSRect(x: 24, y: 113, width: 124, height: 22)
        content.addSubview(widthTitle)
        widthSlider.frame = NSRect(x: 164, y: 108, width: 348, height: 28)
        widthSlider.numberOfTickMarks = 13
        widthSlider.allowsTickMarkValuesOnly = true
        widthSlider.isContinuous = true
        widthSlider.target = self
        widthSlider.action = #selector(changeWidth)
        widthSlider.setAccessibilityLabel("Active edge width, percent")
        content.addSubview(widthSlider)
        widthLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        widthLabel.alignment = .right
        widthLabel.frame = NSRect(x: 532, y: 113, width: 64, height: 22)
        content.addSubview(widthLabel)

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemOrange
        errorLabel.frame = NSRect(x: 24, y: 60, width: 572, height: 40)
        content.addSubview(errorLabel)

        let footer = NSTextField(labelWithString: "Changes save automatically.")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.frame = NSRect(x: 24, y: 27, width: 338, height: 18)
        content.addSubview(footer)
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetSettings))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 390, y: 20, width: 210, height: 32)
        content.addSubview(resetButton)

        let controls = TrackpadEdge.allCases.compactMap { selectors[$0] } + [widthSlider, resetButton]
        for (current, next) in zip(controls, controls.dropFirst() + [controls[0]]) {
            current.nextKeyView = next
        }
        window.initialFirstResponder = selectors[.top]
    }

    private func addSelector(_ edge: TrackpadEdge, frame: NSRect, to content: NSView) {
        let label = NSTextField(labelWithString: edge.title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: frame.minX, y: frame.minY + 30, width: frame.width, height: 20)
        content.addSubview(label)
        let selector = NSPopUpButton(frame: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 28))
        selector.addItems(withTitles: EdgeAction.allCases.map(\.title))
        selector.identifier = NSUserInterfaceItemIdentifier(edge.rawValue)
        selector.target = self
        selector.action = #selector(changeAssignment(_:))
        selector.setAccessibilityLabel("\(edge.title): action")
        content.addSubview(selector)
        selectors[edge] = selector
    }

    private func refreshControls() {
        let settings = store.settings
        for edge in TrackpadEdge.allCases {
            selectors[edge]?.selectItem(at: EdgeAction.allCases.firstIndex(of: settings[edge])!)
        }
        widthSlider.doubleValue = settings.stripWidth * 100
        widthLabel.stringValue = String(format: "%.0f%%", settings.stripWidth * 100)
        diagram.settings = settings
        errorLabel.stringValue = store.loadError ?? ""
        errorLabel.isHidden = store.loadError == nil
    }

    @objc private func changeAssignment(_ sender: NSPopUpButton) {
        guard let identifier = sender.identifier?.rawValue,
              let edge = TrackpadEdge(rawValue: identifier),
              EdgeAction.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        var settings = store.settings
        settings[edge] = EdgeAction.allCases[sender.indexOfSelectedItem]
        save(settings)
    }

    @objc private func changeWidth() {
        var settings = store.settings
        settings.stripWidth = widthSlider.doubleValue.rounded() / 100
        save(settings)
    }

    @objc private func resetSettings() {
        do {
            try store.reset()
            refreshControls()
        } catch { showError(error) }
    }

    private func save(_ settings: EdgeSettings) {
        do {
            try store.update(settings)
            refreshControls()
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        refreshControls()
        errorLabel.stringValue = error.localizedDescription
        errorLabel.isHidden = false
    }
}

@MainActor
private final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

@MainActor
private final class TrackpadDiagramView: NSView {
    var settings = EdgeSettings.defaults { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 5, dy: 5)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
        NSColor.controlBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1.5
        shape.stroke()

        let horizontalThickness = max(4, frame.height * settings.stripWidth)
        let verticalThickness = max(4, frame.width * settings.stripWidth)
        let stripes: [TrackpadEdge: NSRect] = [
            .top: NSRect(x: frame.minX + 15, y: frame.maxY - horizontalThickness - 2, width: frame.width - 30, height: horizontalThickness),
            .bottom: NSRect(x: frame.minX + 15, y: frame.minY + 2, width: frame.width - 30, height: horizontalThickness),
            .left: NSRect(x: frame.minX + 2, y: frame.minY + 15, width: verticalThickness, height: frame.height - 30),
            .right: NSRect(x: frame.maxX - verticalThickness - 2, y: frame.minY + 15, width: verticalThickness, height: frame.height - 30),
        ]
        for (edge, stripe) in stripes {
            color(for: settings[edge]).setFill()
            let radius = min(stripe.width, stripe.height) / 2
            NSBezierPath(roundedRect: stripe, xRadius: radius, yRadius: radius).fill()
        }
        drawCentered("Trackpad", y: frame.midY + 2, font: .systemFont(ofSize: 15, weight: .medium))
        drawCentered("Slide along an edge", y: frame.midY - 20, font: .systemFont(ofSize: 11))
    }

    private func color(for action: EdgeAction) -> NSColor {
        switch action {
        case .volume: .systemBlue
        case .brightness: .systemOrange
        case .disabled: .quaternaryLabelColor
        }
    }

    private func drawCentered(_ text: String, y: CGFloat, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attributes)
    }
}

private enum SettingsPreviewError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Could not render the settings window" }
}
