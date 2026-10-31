import AppKit

@MainActor
final class SettingsWindow: NSObject {
    private let store: SettingsStore
    private let window: NSWindow
    private var selectedEdge: TrackpadEdge = .bottom
    private let edgeChooser = NSSegmentedControl(labels: TrackpadEdge.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let diagram = TrackpadDiagramView(frame: NSRect(x: 30, y: 278, width: 300, height: 196))
    private let edgeTitle = NSTextField(labelWithString: "Bottom Edge")
    private let actionPicker = NSPopUpButton()
    private let modePicker = NSPopUpButton()
    private let sensitivitySlider = NSSlider(value: 1, minValue: 0.25, maxValue: 3, target: nil, action: nil)
    private let sensitivityValue = NSTextField(labelWithString: "1x")
    private let startTapTitle = NSTextField(labelWithString: "Left End Double Tap")
    private let endTapTitle = NSTextField(labelWithString: "Right End Double Tap")
    private let startTapPicker = NSPopUpButton()
    private let endTapPicker = NSPopUpButton()
    private let widthSlider = NSSlider(value: 5, minValue: 3, maxValue: 15, target: nil, action: nil)
    private let widthValue = NSTextField(labelWithString: "5%")
    private let hapticsSwitch = NSButton(checkboxWithTitle: "Haptic Feedback", target: nil, action: nil)
    private let instruction = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(store: SettingsStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 610), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
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
        refreshControls()
        content.layoutSubtreeIfNeeded()
        guard let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw SettingsPreviewError.unavailable }
        window.effectiveAppearance.performAsCurrentDrawingAppearance { content.cacheDisplay(in: content.bounds, to: image) }
        guard let data = image.representation(using: .png, properties: [:]) else { throw SettingsPreviewError.unavailable }
        try data.write(to: url, options: .atomic)
    }

    private func buildContent() {
        let content = SettingsBackgroundView(frame: NSRect(x: 0, y: 0, width: 740, height: 610))
        window.contentView = content
        label("Trackpad Controls", at: NSRect(x: 24, y: 557, width: 692, height: 32), font: .systemFont(ofSize: 24, weight: .semibold), in: content)
        label("Choose an edge, then set its slide and double-tap actions.", at: NSRect(x: 24, y: 528, width: 692, height: 20), secondary: true, in: content)
        edgeChooser.frame = NSRect(x: 24, y: 490, width: 312, height: 28)
        edgeChooser.target = self
        edgeChooser.action = #selector(changeSelectedEdge)
        edgeChooser.setAccessibilityLabel("Selected trackpad edge")
        content.addSubview(edgeChooser)
        diagram.onSelect = { [weak self] edge in self?.selectedEdge = edge; self?.refreshControls() }
        content.addSubview(diagram)

        instruction.frame = NSRect(x: 24, y: 198, width: 312, height: 66)
        instruction.font = .systemFont(ofSize: 12)
        instruction.textColor = .secondaryLabelColor
        content.addSubview(instruction)
        errorLabel.frame = NSRect(x: 24, y: 128, width: 312, height: 62)
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemOrange
        content.addSubview(errorLabel)

        edgeTitle.frame = NSRect(x: 374, y: 487, width: 342, height: 28)
        edgeTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        content.addSubview(edgeTitle)
        label("Slide Action", at: NSRect(x: 374, y: 454, width: 342, height: 20), in: content)
        configure(actionPicker, titles: EdgeAction.allCases.map(\.title), frame: NSRect(x: 374, y: 420, width: 342, height: 28), action: #selector(changeAction), accessibility: "Slide action", in: content)
        label("Adjustment", at: NSRect(x: 374, y: 382, width: 342, height: 20), in: content)
        configure(modePicker, titles: AdjustmentMode.allCases.map(\.title), frame: NSRect(x: 374, y: 348, width: 342, height: 28), action: #selector(changeMode), accessibility: "Adjustment mode", in: content)
        label("Sensitivity", at: NSRect(x: 374, y: 312, width: 342, height: 20), in: content)
        sensitivitySlider.frame = NSRect(x: 374, y: 282, width: 266, height: 28)
        sensitivitySlider.numberOfTickMarks = 12
        sensitivitySlider.allowsTickMarkValuesOnly = true
        sensitivitySlider.isContinuous = true
        sensitivitySlider.target = self
        sensitivitySlider.action = #selector(changeSensitivity)
        sensitivitySlider.setAccessibilityLabel("Relative sensitivity")
        sensitivitySlider.toolTip = "Used by relative adjustment and media gestures."
        content.addSubview(sensitivitySlider)
        sensitivityValue.frame = NSRect(x: 648, y: 287, width: 68, height: 22)
        sensitivityValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        sensitivityValue.alignment = .right
        content.addSubview(sensitivityValue)

        startTapTitle.frame = NSRect(x: 374, y: 246, width: 342, height: 20)
        content.addSubview(startTapTitle)
        configure(startTapPicker, titles: TapAction.allCases.map(\.title), frame: NSRect(x: 374, y: 214, width: 342, height: 28), action: #selector(changeStartTap), accessibility: "Start double-tap action", in: content)
        endTapTitle.frame = NSRect(x: 374, y: 178, width: 342, height: 20)
        content.addSubview(endTapTitle)
        configure(endTapPicker, titles: TapAction.allCases.map(\.title), frame: NSRect(x: 374, y: 146, width: 342, height: 28), action: #selector(changeEndTap), accessibility: "End double-tap action", in: content)

        let divider = NSBox(frame: NSRect(x: 24, y: 115, width: 692, height: 1))
        divider.boxType = .separator
        content.addSubview(divider)
        label("Edge Width", at: NSRect(x: 24, y: 78, width: 112, height: 22), in: content)
        widthSlider.frame = NSRect(x: 140, y: 74, width: 310, height: 28)
        widthSlider.numberOfTickMarks = 13
        widthSlider.allowsTickMarkValuesOnly = true
        widthSlider.isContinuous = true
        widthSlider.target = self
        widthSlider.action = #selector(changeWidth)
        widthSlider.setAccessibilityLabel("Edge width, percent")
        content.addSubview(widthSlider)
        widthValue.frame = NSRect(x: 463, y: 78, width: 54, height: 22)
        widthValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        widthValue.alignment = .right
        content.addSubview(widthValue)
        hapticsSwitch.frame = NSRect(x: 548, y: 76, width: 168, height: 26)
        hapticsSwitch.target = self
        hapticsSwitch.action = #selector(changeHaptics)
        content.addSubview(hapticsSwitch)
        label("Changes are saved automatically.", at: NSRect(x: 24, y: 28, width: 400, height: 20), font: .systemFont(ofSize: 11), secondary: true, in: content)
        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(resetSettings))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 548, y: 20, width: 172, height: 32)
        content.addSubview(reset)
        let controls: [NSView] = [edgeChooser, actionPicker, modePicker, sensitivitySlider, startTapPicker, endTapPicker, widthSlider, hapticsSwitch, reset]
        for (current, next) in zip(controls, controls.dropFirst() + [controls[0]]) { current.nextKeyView = next }
        window.initialFirstResponder = edgeChooser
    }

    @discardableResult
    private func label(_ title: String, at frame: NSRect, font: NSFont = .systemFont(ofSize: 13, weight: .medium), secondary: Bool = false, in content: NSView) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = font
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.frame = frame
        content.addSubview(field)
        return field
    }

    private func configure(_ picker: NSPopUpButton, titles: [String], frame: NSRect, action: Selector, accessibility: String, in content: NSView) {
        picker.addItems(withTitles: titles)
        picker.frame = frame
        picker.target = self
        picker.action = action
        picker.setAccessibilityLabel(accessibility)
        content.addSubview(picker)
    }

    private func refreshControls() {
        let settings = store.settings
        let edge = settings[selectedEdge]
        edgeChooser.selectedSegment = TrackpadEdge.allCases.firstIndex(of: selectedEdge) ?? 0
        edgeTitle.stringValue = "\(selectedEdge.title) Edge"
        actionPicker.selectItem(at: EdgeAction.allCases.firstIndex(of: edge.action) ?? 0)
        let displayedMode = edge.action == .disabled ? edge.mode : edge.effectiveMode
        modePicker.selectItem(at: AdjustmentMode.allCases.firstIndex(of: displayedMode) ?? 0)
        modePicker.isEnabled = edge.action.isLevel
        sensitivitySlider.doubleValue = edge.sensitivity
        sensitivitySlider.isEnabled = edge.action != .disabled && edge.effectiveMode == .relative
        sensitivityValue.stringValue = String(format: "%.2gx", edge.sensitivity)
        sensitivityValue.textColor = sensitivitySlider.isEnabled ? .labelColor : .tertiaryLabelColor
        startTapPicker.selectItem(at: TapAction.allCases.firstIndex(of: edge.startTap) ?? 0)
        endTapPicker.selectItem(at: TapAction.allCases.firstIndex(of: edge.endTap) ?? 0)
        startTapTitle.stringValue = "\(TapZoneEnd.start.title(on: selectedEdge)) End Double Tap"
        endTapTitle.stringValue = "\(TapZoneEnd.end.title(on: selectedEdge)) End Double Tap"
        startTapPicker.setAccessibilityLabel(startTapTitle.stringValue)
        endTapPicker.setAccessibilityLabel(endTapTitle.stringValue)
        widthSlider.doubleValue = settings.stripWidth * 100
        widthValue.stringValue = String(format: "%.0f%%", settings.stripWidth * 100)
        hapticsSwitch.state = settings.hapticsEnabled ? .on : .off
        diagram.settings = settings
        diagram.selectedEdge = selectedEdge
        instruction.stringValue = "Select a side on the diagram. Purple endpoints have a double-tap action.\nRelative adjustment starts from the current system level."
        errorLabel.stringValue = store.loadError ?? ""
        errorLabel.isHidden = store.loadError == nil
    }

    private func updateEdge(_ change: (inout EdgeConfiguration) -> Void) {
        var settings = store.settings
        var edge = settings[selectedEdge]
        change(&edge)
        settings[selectedEdge] = edge
        save(settings)
    }

    private func save(_ settings: EdgeSettings) {
        do { try store.update(settings); refreshControls() }
        catch { refreshControls(); errorLabel.stringValue = error.localizedDescription; errorLabel.isHidden = false }
    }

    @objc private func changeSelectedEdge() {
        guard TrackpadEdge.allCases.indices.contains(edgeChooser.selectedSegment) else { return }
        selectedEdge = TrackpadEdge.allCases[edgeChooser.selectedSegment]
        refreshControls()
    }
    @objc private func changeAction() {
        guard EdgeAction.allCases.indices.contains(actionPicker.indexOfSelectedItem) else { return }
        updateEdge { $0.action = EdgeAction.allCases[actionPicker.indexOfSelectedItem] }
    }
    @objc private func changeMode() {
        guard AdjustmentMode.allCases.indices.contains(modePicker.indexOfSelectedItem) else { return }
        updateEdge { $0.mode = AdjustmentMode.allCases[modePicker.indexOfSelectedItem] }
    }
    @objc private func changeSensitivity() { updateEdge { $0.sensitivity = (sensitivitySlider.doubleValue * 4).rounded() / 4 } }
    @objc private func changeStartTap() {
        guard TapAction.allCases.indices.contains(startTapPicker.indexOfSelectedItem) else { return }
        updateEdge { $0.startTap = TapAction.allCases[startTapPicker.indexOfSelectedItem] }
    }
    @objc private func changeEndTap() {
        guard TapAction.allCases.indices.contains(endTapPicker.indexOfSelectedItem) else { return }
        updateEdge { $0.endTap = TapAction.allCases[endTapPicker.indexOfSelectedItem] }
    }
    @objc private func changeWidth() { var value = store.settings; value.stripWidth = widthSlider.doubleValue.rounded() / 100; save(value) }
    @objc private func changeHaptics() { var value = store.settings; value.hapticsEnabled = hapticsSwitch.state == .on; save(value) }
    @objc private func resetSettings() {
        do { try store.reset(); refreshControls() }
        catch { errorLabel.stringValue = error.localizedDescription; errorLabel.isHidden = false }
    }
}

@MainActor
private final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

@MainActor
private final class TrackpadDiagramView: NSView {
    var settings = EdgeSettings.defaults { didSet { needsDisplay = true } }
    var selectedEdge = TrackpadEdge.bottom { didSet { needsDisplay = true } }
    var onSelect: ((TrackpadEdge) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let frame = bounds.insetBy(dx: 10, dy: 10)
        guard frame.insetBy(dx: -8, dy: -8).contains(point) else { return }
        let distances: [(TrackpadEdge, CGFloat)] = [(.top, abs(point.y - frame.maxY)), (.right, abs(point.x - frame.maxX)), (.bottom, abs(point.y - frame.minY)), (.left, abs(point.x - frame.minX))]
        if let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= 32 { onSelect?(nearest.0) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 10, dy: 10)
        let outline = NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18)
        NSColor.controlBackgroundColor.setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
        for edge in TrackpadEdge.allCases { draw(edge, inside: frame) }
        centered("\(selectedEdge.title) edge", y: frame.midY + 4, font: .systemFont(ofSize: 16, weight: .medium))
        centered(settings[selectedEdge].action.title, y: frame.midY - 19, font: .systemFont(ofSize: 12))
    }

    private func draw(_ edge: TrackpadEdge, inside frame: NSRect) {
        let horizontal = edge.isHorizontal
        let thickness = max(5, (horizontal ? frame.height : frame.width) * settings.stripWidth)
        let strip: NSRect
        switch edge {
        case .top: strip = NSRect(x: frame.minX + 22, y: frame.maxY - thickness - 2, width: frame.width - 44, height: thickness)
        case .right: strip = NSRect(x: frame.maxX - thickness - 2, y: frame.minY + 22, width: thickness, height: frame.height - 44)
        case .bottom: strip = NSRect(x: frame.minX + 22, y: frame.minY + 2, width: frame.width - 44, height: thickness)
        case .left: strip = NSRect(x: frame.minX + 2, y: frame.minY + 22, width: thickness, height: frame.height - 44)
        }
        let shape = NSBezierPath(roundedRect: strip, xRadius: thickness / 2, yRadius: thickness / 2)
        color(for: settings[edge].action).setFill()
        shape.fill()
        if edge == selectedEdge {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: strip.insetBy(dx: -3, dy: -3), xRadius: thickness / 2 + 3, yRadius: thickness / 2 + 3)
            focus.lineWidth = 1.5
            focus.stroke()
        }
        for end in TapZoneEnd.allCases {
            let along = end == .start ? 0.06 : 0.94
            let point = horizontal
                ? NSPoint(x: frame.minX + frame.width * along, y: strip.midY)
                : NSPoint(x: strip.midX, y: frame.minY + frame.height * along)
            let marker = NSBezierPath(ovalIn: NSRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
            if settings[edge][end] != .none {
                NSColor.systemPurple.setFill()
                marker.fill()
                NSColor.controlBackgroundColor.setStroke()
                marker.lineWidth = 1.5
                marker.stroke()
            } else {
                NSColor.separatorColor.setStroke()
                marker.lineWidth = 1
                marker.stroke()
            }
        }
    }

    private func color(for action: EdgeAction) -> NSColor {
        switch action {
        case .volume: .systemBlue
        case .brightness: .systemOrange
        case .tracks, .seek: .systemPurple
        case .disabled: .quaternaryLabelColor
        }
    }
    private func centered(_ text: String, y: CGFloat, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attributes)
    }
}

private enum SettingsPreviewError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Could not render the settings preview." }
}
