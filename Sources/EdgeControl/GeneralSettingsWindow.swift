import AppKit
import UniformTypeIdentifiers

@MainActor
final class GeneralSettingsWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: SettingsStore
    private let launchAtLogin: LaunchAtLogin
    private let loginSwitch = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let window: NSWindow
    private let table = NSTableView()
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(store: SettingsStore, launchAtLogin: LaunchAtLogin = LaunchAtLogin()) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.title = "EdgeControl General Settings"
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
    func windowDidBecomeKey(_ notification: Notification) { refreshControls() }

    func renderPreview(to url: URL, appearance: NSAppearance.Name = .aqua) throws {
        guard let content = window.contentView else { throw GeneralPreviewError() }
        window.appearance = NSAppearance(named: appearance)
        content.appearance = window.appearance
        refreshControls()
        content.layoutSubtreeIfNeeded()
        guard let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw GeneralPreviewError() }
        window.effectiveAppearance.performAsCurrentDrawingAppearance { content.cacheDisplay(in: content.bounds, to: image) }
        guard let data = image.representation(using: .png, properties: [:]) else { throw GeneralPreviewError() }
        try data.write(to: url, options: .atomic)
    }

    private func buildContent() {
        let content = GeneralSettingsBackgroundView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
        window.contentView = content
        label("General", frame: NSRect(x: 20, y: 326, width: 520, height: 25),
              font: .systemFont(ofSize: 20, weight: .semibold), in: content)
        loginSwitch.frame = NSRect(x: 20, y: 294, width: 240, height: 24)
        loginSwitch.target = self
        loginSwitch.action = #selector(changeLaunchAtLogin)
        content.addSubview(loginSwitch)
        loginStatus.frame = NSRect(x: 20, y: 267, width: 520, height: 25)
        loginStatus.font = .systemFont(ofSize: 11)
        loginStatus.textColor = .secondaryLabelColor
        content.addSubview(loginStatus)
        label("Pause gestures in selected apps", frame: NSRect(x: 20, y: 242, width: 520, height: 22),
              font: .systemFont(ofSize: 13, weight: .semibold), in: content)
        label("Gestures resume when you switch to another app.", frame: NSRect(x: 20, y: 222, width: 520, height: 18),
              font: .systemFont(ofSize: 11), secondary: true, in: content)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Application"))
        column.width = 518
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.frame = NSRect(x: 0, y: 0, width: 518, height: 130)
        table.rowHeight = 26
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.allowsMultipleSelection = true
        table.setAccessibilityLabel("Applications where gestures are paused")
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 82, width: 520, height: 130))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        content.addSubview(scroll)

        let add = NSButton(title: "Add…", target: self, action: #selector(addApplications))
        add.bezelStyle = .rounded
        add.frame = NSRect(x: 16, y: 38, width: 82, height: 30)
        content.addSubview(add)
        removeButton.target = self
        removeButton.action = #selector(removeApplications)
        removeButton.bezelStyle = .rounded
        removeButton.frame = NSRect(x: 100, y: 38, width: 86, height: 30)
        content.addSubview(removeButton)
        label("Saved automatically. Shared across profiles.", frame: NSRect(x: 196, y: 44, width: 344, height: 18),
              font: .systemFont(ofSize: 11), secondary: true, in: content)
        errorLabel.frame = NSRect(x: 20, y: 3, width: 520, height: 30)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemOrange
        content.addSubview(errorLabel)
        loginSwitch.nextKeyView = add
        add.nextKeyView = table
        table.nextKeyView = removeButton
        removeButton.nextKeyView = loginSwitch
        window.initialFirstResponder = loginSwitch
    }

    private func label(_ text: String, frame: NSRect, font: NSFont, secondary: Bool = false, in content: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = font
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        content.addSubview(label)
    }

    private func refreshControls() {
        loginSwitch.state = launchAtLogin.isRegistered ? .on : .off
        loginStatus.stringValue = launchAtLogin.statusText
        table.reloadData()
        removeButton.isEnabled = !table.selectedRowIndexes.isEmpty
        errorLabel.stringValue = store.loadError ?? ""
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.excludedAppIDs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard store.excludedAppIDs.indices.contains(row) else { return nil }
        let bundleID = store.excludedAppIDs[row]
        let identifier = NSUserInterfaceItemIdentifier("ExcludedApplication")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.font = .systemFont(ofSize: 13)
        cell.lineBreakMode = .byTruncatingTail
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let bundle = Bundle(url: url)
            cell.stringValue = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? FileManager.default.displayName(atPath: url.path)
        } else {
            cell.stringValue = bundleID
        }
        cell.toolTip = bundleID
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = !table.selectedRowIndexes.isEmpty
    }

    @objc private func changeLaunchAtLogin() {
        do { try launchAtLogin.setEnabled(loginSwitch.state == .on); refreshControls() }
        catch { refreshControls(); errorLabel.stringValue = error.localizedDescription }
    }

    @objc private func addApplications() {
        guard let ownID = Bundle.main.bundleIdentifier else {
            errorLabel.stringValue = "The application identity is unavailable. Open the built application and try again."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Pause Gestures"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        guard panel.runModal() == .OK else { return }
        var bundleIDs = store.excludedAppIDs
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else {
                errorLabel.stringValue = "The selected application has no bundle identifier."
                return
            }
            guard bundleID != ownID else { continue }
            if !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
        }
        guard bundleIDs != store.excludedAppIDs else {
            errorLabel.stringValue = "The selected apps are already listed, or are EdgeControl itself."
            return
        }
        save(bundleIDs)
    }

    @objc private func removeApplications() {
        let selected = table.selectedRowIndexes
        guard !selected.isEmpty else { return }
        let remaining = store.excludedAppIDs.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
        save(remaining)
    }

    private func save(_ bundleIDs: [String]) {
        do { try store.setExcludedAppIDs(bundleIDs); refreshControls() }
        catch { errorLabel.stringValue = error.localizedDescription }
    }
}

@MainActor
private final class GeneralSettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

private struct GeneralPreviewError: LocalizedError {
    var errorDescription: String? { "Could not render the general settings preview." }
}
