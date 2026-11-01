import AppKit
import Darwin

@main
enum EdgeControlMain {
    @MainActor static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] {
            print("Usage: EdgeControl [--diagnose | --render-previews DIRECTORY]\nDiagnostic mode never changes levels or sends commands.")
            return
        }
        if arguments.count == 2, arguments[0] == "--render-previews" {
            do { try renderPreviews(at: URL(fileURLWithPath: arguments[1], isDirectory: true)) }
            catch { writeError(error.localizedDescription); exit(1) }
            return
        }
        guard arguments.isEmpty || arguments == ["--diagnose"] else {
            writeError("Usage: EdgeControl [--diagnose | --render-previews DIRECTORY]")
            exit(2)
        }
        let app = NSApplication.shared
        let controller = ApplicationController(diagnostic: arguments == ["--diagnose"])
        app.setActivationPolicy(.accessory)
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    @MainActor private static func renderPreviews(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let domain = "local.edgecontrol.preview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else { throw CocoaError(.fileWriteUnknown) }
        defer { defaults.removePersistentDomain(forName: domain) }
        let window = SettingsWindow(store: SettingsStore(defaults: defaults, previousDefaults: nil))
        let hud = LevelHUD()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            app.appearance = NSAppearance(named: appearance)
            try window.renderPreview(to: directory.appendingPathComponent("settings-\(name).png"), appearance: appearance)
            try hud.renderPreview(to: directory.appendingPathComponent("profile-\(name).png"), appearance: appearance, profileName: "Everyday")
            for action in [EdgeAction.volume, .brightness, .keyboardBrightness, .tracks, .seek] {
                try hud.renderPreview(to: directory.appendingPathComponent("\(action.rawValue)-\(name).png"),
                                      action: action, appearance: appearance)
            }
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
    private let keyboard = KeyboardBacklight()
    private let media = MediaController()
    private let settings = SettingsStore()
    private let hud = LevelHUD()
    private let haptics = HapticFeedback()
    private var gesture = EdgeGesture()
    private var taps = DoubleTapGesture()
    private var level = LevelAccumulator()
    private var mediaMotion = MediaMotion()
    private var settingsWindow: SettingsWindow?
    private var activeAction: EdgeAction?
    private var lastAppliedLevel: Int?
    private var clickSuppressionUntil: Double?
    private var controlErrors: [EdgeAction: String] = [:]
    private var menu: StatusMenu?
    private let diagnostic: Bool
    private var isPaused = false
    private var errorMessage: String?
    private var hapticError: String?
    private var lastProfileID: UUID?
    private var suspensions: Set<String> = []
    private var acceptedAfter = Double.infinity
    private var lastFrameAt: Double?
    private var lastDiagnosticAt = 0.0
    private var watchdog: Timer?

    init(diagnostic: Bool) { self.diagnostic = diagnostic }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(
            onTogglePause: { [weak self] in self?.togglePause() },
            onQuit: { NSApplication.shared.terminate(nil) },
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onSelectProfile: { [weak self] id in self?.selectProfile(id) }
        )
        input.onFrame = { [weak self] frame in self?.handle(frame) }
        input.onError = { [weak self] message in self?.fail(message) }
        cursor.onError = { [weak self] message in self?.fail(message) }
        audio.onChange = { [weak self] in self?.outputChanged(.volume) }
        brightness.onChange = { [weak self] in self?.outputChanged(.brightness) }
        lastProfileID = settings.activeProfileID
        settings.onChange = { [weak self] _ in self?.settingsChanged() }
        observeSession()
        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(checkInput), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        if !diagnostic {
            // Readiness errors remain specific to an action; the other action can still run.
            do { try audio.start() } catch { controlErrors[.volume] = error.localizedDescription }
            do { try brightness.start() } catch { controlErrors[.brightness] = error.localizedDescription }
            do { try keyboard.start() } catch { controlErrors[.keyboardBrightness] = error.localizedDescription }
        }
        startInput()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.invalidate()
        watchdog = nil
        stopInput()
        audio.stop()
        brightness.stop()
        keyboard.stop()
        settingsWindow?.close()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        menu?.remove()
    }

    private func startInput() {
        resetInput()
        guard !isPaused, suspensions.isEmpty else { cursor.stop(); updateMenu(); return }
        do {
            guard CursorCapture.hasPermission else { fail("Accessibility permission is required"); return }
            try cursor.start()
            acceptedAfter = ProcessInfo.processInfo.systemUptime
            try input.start()
            hapticError = nil
            if !diagnostic, settings.settings.hapticsEnabled {
                do { try haptics.start(deviceID: input.deviceIdentifier()) }
                catch { hapticError = "Haptics: \(error.localizedDescription)" }
            }
            errorMessage = nil
            updateMenu()
        } catch { fail(error.localizedDescription) }
    }

    private func resetInput() {
        acceptedAfter = .infinity
        gesture.reset()
        taps.reset()
        level.reset()
        mediaMotion.reset()
        haptics.reset()
        cursor.releaseAll()
        do { try haptics.stop() }
        catch { hapticError = "Haptics: \(error.localizedDescription)" }
        input.stop()
        hud.hide()
        activeAction = nil
        lastAppliedLevel = nil
        clickSuppressionUntil = nil
        lastFrameAt = nil
    }

    private func stopInput() {
        resetInput()
        cursor.stop()
    }

    private func settingsChanged() {
        let switched = lastProfileID != settings.activeProfileID
        lastProfileID = settings.activeProfileID
        startInput()
        settingsWindow?.refresh()
        if switched { hud.showProfile(settings.activeProfileName) }
    }

    private func selectProfile(_ id: UUID) {
        do { try settings.selectProfile(id: id) }
        catch { fail(error.localizedDescription) }
    }

    private func handle(_ frame: TrackpadFrame) {
        guard !isPaused, suspensions.isEmpty, input.isRunning, frame.timestamp >= acceptedAfter else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.5 else {
            fail("Trackpad data arrived too late; resume to retry")
            return
        }
        lastFrameAt = now
        let update = gesture.process(frame, settings: settings.gestureSettings, precision: CGEventSource.flagsState(.combinedSessionState).contains(.maskShift))
        let tap = taps.process(frame, settings: settings.gestureSettings, sliding: update.isActive)
        clickSuppressionUntil = tap.suppressionUntil
        cursor.setClickSuppression(tap.suppressClicks && (tap.suppressionUntil.map { $0 > now } ?? false))
        do {
            if let command = tap.command {
                try perform(command.action)
                if command.action == .nextProfile {
                    // Profile changes reset recognition, but the native tap-to-click tail is still reserved.
                    clickSuppressionUntil = tap.suppressionUntil
                    cursor.setClickSuppression(tap.suppressionUntil.map { $0 > ProcessInfo.processInfo.systemUptime } ?? false)
                    return
                }
            }
            switch update {
            case .inactive:
                cursor.release()
                if activeAction != nil {
                    hud.finish()
                    activeAction = nil
                    lastAppliedLevel = nil
                    level.reset()
                    mediaMotion.reset()
                }
            case let .active(_, action, change):
                if activeAction == nil {
                    let relative: Bool
                    if case .relative = change { relative = true } else { relative = false }
                    try begin(action, relative: relative)
                }
                if let change { try apply(change, action: action) }
            }
        } catch { fail(error.localizedDescription); return }
        if diagnostic, now - lastDiagnosticAt >= 0.1 {
            let positions = frame.contacts.map {
                String(format: "id=%d x=%.4f y=%.4f", $0.id, $0.x, $0.y)
            }.joined(separator: "; ")
            print("contacts=\(frame.contacts.count) active=\(update.isActive) \(positions)")
            lastDiagnosticAt = now
        }
    }

    private func begin(_ action: EdgeAction, relative: Bool) throws {
        level.reset()
        mediaMotion.reset()
        haptics.reset()
        lastAppliedLevel = nil
        if !diagnostic {
            switch action {
            case .volume: try audio.refresh()
            case .brightness: try brightness.refresh()
            case .keyboardBrightness: try keyboard.refresh()
            case .tracks, .seek: break
            case .disabled: throw ApplicationControlError("This edge is disabled")
            }
            if action.isLevel, relative {
                let initial: Int
                switch action {
                case .volume: initial = try audio.readVolumePercent()
                case .brightness: initial = try brightness.readBrightnessPercent()
                case .keyboardBrightness: initial = try keyboard.readBrightnessPercent()
                default: throw ApplicationControlError("This action does not control a level")
                }
                try level.start(at: initial)
            }
        }
        try cursor.acquire()
        activeAction = action
    }

    private func apply(_ change: LevelChange, action: EdgeAction) throws {
        if diagnostic {
            switch change {
            case .absolute(let percent): hud.show(action: action, percent: percent, diagnostic: true)
            case .relative(let delta):
                if ProcessInfo.processInfo.systemUptime - lastDiagnosticAt >= 0.1 {
                    print("action=\(action.rawValue) delta=\(delta) percentage points; no output requested")
                }
                hud.showSymbol("arrow.left.and.right", accessibilityLabel: "Diagnostic relative movement")
            }
            return
        }
        if action.isLevel {
            let percent = try level.apply(change)
            guard percent != lastAppliedLevel else { return }
            switch action {
            case .volume: try audio.setVolume(percent: percent)
            case .brightness: try brightness.setBrightness(percent: percent)
            case .keyboardBrightness: try keyboard.setBrightness(percent: percent)
            default: throw ApplicationControlError("This action does not control a level")
            }
            lastAppliedLevel = percent
            controlErrors[action] = nil
            updateMenu()
            hud.show(action: action, percent: percent)
            emitHaptic { try haptics.levelChanged(to: percent, enabled: settings.settings.hapticsEnabled) }
        } else if let command = try mediaMotion.consume(change, action: action) {
            try perform(command)
        }
    }

    private func perform(_ action: TapAction) throws {
        guard action != .none else { return }
        if diagnostic {
            print("action=\(action.rawValue); no command requested")
            hud.showSymbol(action.symbol, accessibilityLabel: "Diagnostic: \(action.title)")
            return
        }
        if action == .nextProfile {
            try settings.nextProfile()
        } else if action == .toggleKeyboardBacklight {
            try keyboard.refresh()
            let isOn = try keyboard.toggle()
            controlErrors[.keyboardBrightness] = nil
            hud.showSymbol(isOn ? "keyboard.fill" : "keyboard", accessibilityLabel: isOn ? "Keyboard backlight on" : "Keyboard backlight off")
        } else if action == .mute {
            try audio.refresh()
            let muted = try audio.toggleMute()
            controlErrors[.volume] = nil
            hud.showSymbol(muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           accessibilityLabel: muted ? "Muted" : "Unmuted")
        } else {
            try media.perform(action)
            hud.showSymbol(action.symbol, accessibilityLabel: action.title)
        }
        emitHaptic { try haptics.actionPerformed(enabled: settings.settings.hapticsEnabled) }
        updateMenu()
    }

    private func emitHaptic(_ request: () throws -> Void) {
        guard haptics.isReady else { return }
        do { try request(); hapticError = nil }
        catch { hapticError = "Haptics: \(error.localizedDescription)" }
        updateMenu()
    }

    @objc private func checkInput() {
        let now = ProcessInfo.processInfo.systemUptime
        if let deadline = clickSuppressionUntil, now >= deadline {
            cursor.setClickSuppression(false)
            clickSuppressionUntil = nil
        }
        if cursor.isCaptured, let lastFrameAt, now - lastFrameAt >= 0.5 {
            fail("Trackpad signal was lost; resume to retry")
        }
    }

    private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(store: settings) }
        settingsWindow?.show()
    }

    private func outputChanged(_ action: EdgeAction) {
        controlErrors[action] = nil
        if activeAction == nil || activeAction == action { startInput() } else { updateMenu() }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused { errorMessage = nil; stopInput(); updateMenu() } else { startInput() }
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
        if CursorCapture.hasPermission { isPaused = false; startInput() } else { updateMenu() }
    }

    private func updateMenu() {
        let unavailable = EdgeAction.allCases.first { action in
            action.isLevel && controlErrors[action] != nil &&
                TrackpadEdge.allCases.contains { settings.settings[$0].action == action }
        }
        let warning = unavailable.flatMap { action in controlErrors[action].map { "\(action.title): \($0)" } }
        let feedbackWarning = settings.settings.hapticsEnabled ? hapticError : nil
        let status = errorMessage ?? (!suspensions.isEmpty ? "Session suspended" :
            (isPaused ? "Paused" : (diagnostic ? "Diagnostic: outputs unchanged" : (warning ?? feedbackWarning ?? "Ready"))))
        menu?.updateProfiles(settings.profiles, activeID: settings.activeProfileID)
        menu?.update(status: status, isPaused: isPaused, needsPermission: !CursorCapture.hasPermission)
    }

    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(sessionChanged(_:)), name: name, object: nil)
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(sessionChanged(_:)), name: .init(name), object: nil)
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
        if suspensions.isEmpty { startInput() } else { stopInput(); updateMenu() }
    }
}

private struct ApplicationControlError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
