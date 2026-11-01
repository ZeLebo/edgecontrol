import AppKit

@MainActor
enum KeyboardShortcutEditor {
    static func renderPreview(to url: URL, initial: KeyboardShortcut, appearance: NSAppearance.Name) throws {
        let view = ShortcutEditorView(initial: initial)
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        view.appearance = window.appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        window.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        window.close()
    }

    static func choose(initial: KeyboardShortcut, title: String) -> KeyboardShortcut? {
        let editor = ShortcutEditorView(initial: initial)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Record a shortcut or choose a key and modifiers."
        alert.accessoryView = editor
        let save = alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        save.isEnabled = initial.isValid
        editor.onChange = { [weak save] value in save?.isEnabled = value.isValid }
        let response = alert.runModal()
        editor.stopRecording()
        return response == .alertFirstButtonReturn && editor.shortcut.isValid ? editor.shortcut : nil
    }
}

@MainActor
func shortcut(from event: NSEvent) -> KeyboardShortcut? {
    guard event.type == .keyDown else { return nil }
    var modifiers: ShortcutModifiers = []
    for (flag, modifier) in [(NSEvent.ModifierFlags.command, ShortcutModifiers.command),
                             (.option, .option), (.control, .control), (.shift, .shift)] {
        if event.modifierFlags.contains(flag) { modifiers.insert(modifier) }
    }
    if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
       (0xF718...0xF71B).contains(scalar.value) {
        return KeyboardShortcut.functionKey(Int(scalar.value - 0xF718) + 21, modifiers: modifiers)
    }
    let value = KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers)
    return value.isValid ? value : nil
}

@MainActor
private final class ShortcutEditorView: NSView {
    private(set) var shortcut: KeyboardShortcut
    var onChange: ((KeyboardShortcut) -> Void)?
    private let recorder: NativeKeyRecorderButton
    private let preset = NSPopUpButton()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let modifierButtons: [(ShortcutModifiers, NSButton)] = [
        (.command, NSButton(checkboxWithTitle: "⌘ Cmd", target: nil, action: nil)),
        (.option, NSButton(checkboxWithTitle: "⌥ Option", target: nil, action: nil)),
        (.control, NSButton(checkboxWithTitle: "⌃ Ctrl", target: nil, action: nil)),
        (.shift, NSButton(checkboxWithTitle: "⇧ Shift", target: nil, action: nil)),
    ]

    init(initial: KeyboardShortcut) {
        shortcut = initial
        recorder = NativeKeyRecorderButton(shortcut: initial)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        recorder.frame = NSRect(x: 0, y: 136, width: 400, height: 36)
        recorder.onCapture = { [weak self] value in self?.update(value) }
        addSubview(recorder)

        let label = NSTextField(labelWithString: "Key")
        label.frame = NSRect(x: 0, y: 98, width: 48, height: 22)
        addSubview(label)
        preset.addItems(withTitles: ["Custom", "Escape"] + (13...24).map { "F\($0)" })
        preset.frame = NSRect(x: 54, y: 94, width: 346, height: 28)
        preset.target = self
        preset.action = #selector(changePreset)
        preset.setAccessibilityLabel("Shortcut key preset")
        addSubview(preset)

        let row = NSStackView(views: modifierButtons.map(\.1))
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.frame = NSRect(x: 0, y: 56, width: 400, height: 26)
        addSubview(row)
        for ((_, button), name) in zip(modifierButtons, ["Command", "Option", "Control", "Shift"]) {
            button.target = self
            button.action = #selector(changeModifiers)
            button.setAccessibilityLabel("\(name) modifier")
        }
        notice.frame = NSRect(x: 0, y: 0, width: 400, height: 44)
        notice.font = .systemFont(ofSize: 11)
        notice.textColor = .secondaryLabelColor
        addSubview(notice)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }

    func stopRecording() { recorder.stopRecording() }

    private func update(_ value: KeyboardShortcut) {
        shortcut = value
        recorder.setShortcut(value)
        refresh()
        onChange?(value)
    }

    private func refresh() {
        if shortcut.keyCode == 53, shortcut.extendedFunctionKey == nil {
            preset.selectItem(at: 1)
        } else if let function = shortcut.functionNumber, (13...24).contains(function) {
            preset.selectItem(at: function - 11)
        } else {
            preset.selectItem(at: 0)
        }
        for (modifier, button) in modifierButtons { button.state = shortcut.modifiers.contains(modifier) ? .on : .off }
        notice.stringValue = shortcut.compatibilityNotice ?? "Click the shortcut to record. Escape cancels recording."
    }

    private var selectedModifiers: ShortcutModifiers {
        modifierButtons.reduce(into: []) { value, item in
            if item.1.state == .on { value.insert(item.0) }
        }
    }

    @objc private func changePreset() {
        recorder.stopRecording()
        if preset.indexOfSelectedItem == 0 {
            recorder.startRecording()
        } else if preset.indexOfSelectedItem == 1 {
            update(KeyboardShortcut(keyCode: 53, modifiers: selectedModifiers))
        } else if let value = KeyboardShortcut.functionKey(preset.indexOfSelectedItem + 11, modifiers: selectedModifiers) {
            update(value)
        }
    }

    @objc private func changeModifiers() {
        var value = shortcut
        value.modifiers = selectedModifiers
        update(value)
    }
}

@MainActor
private final class NativeKeyRecorderButton: NSButton {
    var onCapture: ((KeyboardShortcut) -> Void)?
    private var currentShortcut: KeyboardShortcut
    private var isRecording = false
    override var acceptsFirstResponder: Bool { true }

    init(shortcut: KeyboardShortcut) {
        self.currentShortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 16, weight: .medium)
        target = self
        action = #selector(startRecording)
        toolTip = "Record a shortcut. Some system combinations are reserved by macOS."
        setAccessibilityLabel("Record keyboard shortcut")
        stopRecording()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setShortcut(_ value: KeyboardShortcut) {
        currentShortcut = value
        stopRecording()
    }

    @objc func startRecording() {
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        title = "Press Shortcut…"
        setAccessibilityValue("Recording shortcut")
    }

    func stopRecording() {
        isRecording = false
        title = currentShortcut.displayName
        setAccessibilityValue(currentShortcut.displayName)
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, window?.firstResponder === self else { super.keyDown(with: event); return }
        capture(event)
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            stopRecording()
            return
        }
        guard let value = shortcut(from: event) else { return }
        currentShortcut = value
        stopRecording()
        onCapture?(value)
    }
}
