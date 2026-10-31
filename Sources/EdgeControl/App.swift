import AppKit
import Darwin

@main
enum EdgeControlMain {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] {
            print("Usage: EdgeControl [--diagnose | --render-previews DIRECTORY]\n--diagnose: show samples and target levels without changing volume or brightness.")
            return
        }
        if arguments.count == 2, arguments[0] == "--render-previews" {
            do { try renderPreviews(at: URL(fileURLWithPath: arguments[1], isDirectory: true)) }
            catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        guard arguments.isEmpty || arguments == ["--diagnose"] else {
            FileHandle.standardError.write(Data("Usage: EdgeControl [--diagnose | --render-previews DIRECTORY]\n".utf8))
            exit(2)
        }
        let app = NSApplication.shared
        let controller = ApplicationController(diagnostic: arguments == ["--diagnose"])
        app.setActivationPolicy(.accessory)
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }

    @MainActor
    private static func renderPreviews(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let domain = "local.edgecontrol.preview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else { return }
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)
        let window = SettingsWindow(store: store)
        let hud = LevelHUD()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            app.appearance = NSAppearance(named: appearance)
            try window.renderPreview(to: directory.appendingPathComponent("settings-\(name).png"), appearance: appearance)
            try hud.renderPreview(to: directory.appendingPathComponent("volume-\(name).png"), appearance: appearance)
            try hud.renderPreview(to: directory.appendingPathComponent("brightness-\(name).png"), action: .brightness, appearance: appearance)
        }
        window.close()
        print("Previews saved: \(directory.path)")
    }
}

@MainActor
final class ApplicationController: NSObject, NSApplicationDelegate {
    private let input = TrackpadInput()
    private let cursor = CursorCapture()
    private let audio = AudioOutput()
    private let brightness = BrightnessOutput()
    private let settings = SettingsStore()
    private let hud = LevelHUD()
    private var gesture = EdgeGesture()
    private var settingsWindow: SettingsWindow?
    private var activeAction: EdgeAction?
    private var controlErrors: [EdgeAction: String] = [:]
    private var menu: StatusMenu?
    private let diagnostic: Bool
    private var isPaused = false
    private var errorMessage: String?
    private var suspensions: Set<String> = []
    private var acceptedAfter = Double.infinity
    private var lastFrameAt: Double?
    private var lastDiagnosticAt = 0.0
    private var watchdog: Timer?

    init(diagnostic: Bool) {
        self.diagnostic = diagnostic
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(
            onTogglePause: { [weak self] in self?.togglePause() },
            onQuit: { NSApplication.shared.terminate(nil) },
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        input.onFrame = { [weak self] frame in self?.handle(frame) }
        input.onError = { [weak self] message in self?.fail(message) }
        cursor.onError = { [weak self] message in self?.fail(message) }
        audio.onChange = { [weak self] in self?.outputChanged(.volume) }
        brightness.onChange = { [weak self] in self?.outputChanged(.brightness) }
        settings.onChange = { [weak self] _ in self?.startInput() }
        observeSession()
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(checkInput), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        if !diagnostic {
            // An unavailable output must not disable the other action at startup.
            do { try audio.start() } catch { controlErrors[.volume] = error.localizedDescription }
            do { try brightness.start() } catch { controlErrors[.brightness] = error.localizedDescription }
        }
        startInput()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.invalidate()
        watchdog = nil
        stopInput()
        audio.stop()
        brightness.stop()
        settingsWindow?.close()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        menu?.remove()
    }

    private func startInput() {
        stopInput()
        guard !isPaused, suspensions.isEmpty else {
            updateMenu()
            return
        }
        do {
            guard CursorCapture.hasPermission else {
                fail("Accessibility permission is required")
                return
            }
            try cursor.start()
            acceptedAfter = ProcessInfo.processInfo.systemUptime
            try input.start()
            errorMessage = nil
            updateMenu()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func stopInput() {
        acceptedAfter = .infinity
        gesture.reset()
        cursor.stop()
        input.stop()
        hud.hide()
        activeAction = nil
        lastFrameAt = nil
    }

    private func handle(_ frame: TrackpadFrame) {
        guard !isPaused, suspensions.isEmpty, input.isRunning,
              frame.timestamp >= acceptedAfter else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Queued frames must never apply an old gesture after the app stalls.
        guard frame.timestamp.isFinite, frame.timestamp <= now,
              now - frame.timestamp < 0.5 else {
            fail("Trackpad input is delayed; resume the app")
            return
        }
        lastFrameAt = now
        let update = gesture.process(frame, settings: settings.settings)
        switch update {
        case .inactive:
            cursor.release()
            if activeAction != nil {
                hud.finish()
                activeAction = nil
            }
        case let .active(_, action, percent):
            do {
                if activeAction == nil {
                    if !diagnostic {
                        switch action {
                        case .volume: try audio.refresh()
                        case .brightness: try brightness.refresh()
                        case .disabled: throw ApplicationControlError("This edge is disabled")
                        }
                    }
                    try cursor.acquire()
                    activeAction = action
                }
                if let percent {
                    if diagnostic {
                        print("action=\(action.rawValue) target=\(percent)% (system levels unchanged)")
                    } else {
                        switch action {
                        case .volume: try audio.setVolume(percent: percent)
                        case .brightness: try brightness.setBrightness(percent: percent)
                        case .disabled: throw ApplicationControlError("This edge is disabled")
                        }
                        controlErrors[action] = nil
                        updateMenu()
                    }
                    hud.show(action: action, percent: percent, diagnostic: diagnostic)
                }
            } catch {
                fail(error.localizedDescription)
                return
            }
        }
        if diagnostic, now - lastDiagnosticAt >= 0.1 {
            let positions = frame.contacts.map {
                String(format: "id=%d x=%.4f y=%.4f", $0.id, $0.x, $0.y)
            }.joined(separator: "; ")
            print("contacts=\(frame.contacts.count) active=\(update.isActive) \(positions)")
            lastDiagnosticAt = now
        }
    }

    private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(store: settings) }
        settingsWindow?.show()
    }

    private func outputChanged(_ action: EdgeAction) {
        controlErrors[action] = nil
        if activeAction == nil || activeAction == action { startInput() }
        else { updateMenu() }
    }

    @objc private func checkInput() {
        guard cursor.isCaptured, let lastFrameAt else { return }
        if ProcessInfo.processInfo.systemUptime - lastFrameAt >= 0.5 {
            fail("Trackpad input was lost; resume the app")
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            errorMessage = nil
            stopInput()
            updateMenu()
        } else {
            startInput()
        }
    }

    private func fail(_ message: String) {
        stopInput()
        isPaused = true
        errorMessage = message
        updateMenu()
        if diagnostic { print("error: \(message)") }
    }

    private func requestPermission() {
        CursorCapture.requestPermission()
        if CursorCapture.hasPermission {
            isPaused = false
            startInput()
        } else {
            updateMenu()
        }
    }

    private func updateMenu() {
        let unavailable = EdgeAction.allCases.first { action in
            action != .disabled && controlErrors[action] != nil &&
                TrackpadEdge.allCases.contains { settings.settings[$0] == action }
        }
        let warning = unavailable.flatMap { action in controlErrors[action].map { "\(action.title): \($0)" } }
        let status = errorMessage ?? (!suspensions.isEmpty ? "Session suspended" :
            (isPaused ? "Paused" : (diagnostic ? "Diagnostic: system levels unchanged" : (warning ?? "Ready"))))
        menu?.update(status: status, isPaused: isPaused, needsPermission: !CursorCapture.hasPermission)
    }

    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(sessionChanged(_:)), name: name, object: nil)
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            distributed.addObserver(self, selector: #selector(sessionChanged(_:)), name: .init(name), object: nil)
        }
    }

    @objc private func sessionChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: suspensions.insert("sleep")
        case NSWorkspace.didWakeNotification: suspensions.remove("sleep")
        case NSWorkspace.sessionDidResignActiveNotification: suspensions.insert("session")
        case NSWorkspace.sessionDidBecomeActiveNotification: suspensions.remove("session")
        case .init("com.apple.screenIsLocked"): suspensions.insert("lock")
        case .init("com.apple.screenIsUnlocked"): suspensions.remove("lock")
        default: return
        }
        if suspensions.isEmpty { startInput() } else {
            stopInput()
            updateMenu()
        }
    }
}

private struct ApplicationControlError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
