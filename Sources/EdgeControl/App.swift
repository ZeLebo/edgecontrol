import AppKit

@main
enum EdgeControlMain {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().contains("--help") {
            print("EdgeControl: absolute volume on the bottom trackpad edge")
            return
        }
        let app = NSApplication.shared
        let controller = VolumeApplication()
        app.setActivationPolicy(.accessory)
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}

@MainActor
final class VolumeApplication: NSObject, NSApplicationDelegate {
    private let input = TrackpadInput()
    private let cursor = CursorCapture()
    private let audio = AudioOutput()
    private var gesture = VolumeGesture()
    private var menu: StatusMenu?
    private var paused = false
    private var suspended = Set<String>()
    private var failure: String?
    private var acceptedAfter = Double.infinity
    private var lastFrame: Double?
    private var watchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(onToggle: { [weak self] in self?.togglePause() }, onPermission: { [weak self] in
            CursorCapture.requestPermission()
            if CursorCapture.hasPermission { self?.paused = false; self?.start() }
        })
        input.onFrame = { [weak self] frame in self?.handle(frame) }
        input.onError = { [weak self] message in self?.fail(message) }
        cursor.onError = { [weak self] message in self?.fail(message) }
        audio.onChange = { [weak self] in self?.start() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(sessionChanged(_:)), name: name, object: nil)
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(sessionChanged(_:)), name: .init(name), object: nil)
        }
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(checkInput), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        do { try audio.start(); start() } catch { fail(error.localizedDescription) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.invalidate()
        stop()
        audio.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        menu?.remove()
    }
    private func start() {
        stop()
        guard !paused, suspended.isEmpty else { updateMenu(); return }
        do {
            guard CursorCapture.hasPermission else { fail("Accessibility permission is required"); return }
            try audio.refresh()
            try cursor.start()
            acceptedAfter = ProcessInfo.processInfo.systemUptime
            try input.start()
            failure = nil
            updateMenu()
        } catch { fail(error.localizedDescription) }
    }
    private func stop() {
        acceptedAfter = .infinity
        gesture.reset()
        cursor.stop()
        input.stop()
        lastFrame = nil
    }
    private func handle(_ frame: TrackpadFrame) {
        guard !paused, suspended.isEmpty, input.isRunning, frame.timestamp >= acceptedAfter else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.5 else {
            fail("Trackpad data arrived too late; resume to retry")
            return
        }
        lastFrame = now
        let update = gesture.process(frame)
        guard update.isActive else { cursor.release(); return }
        do {
            if !cursor.isCaptured { try cursor.acquire() }
            if let percent = update.percent { try audio.setVolume(percent: percent) }
        } catch { fail(error.localizedDescription) }
    }
    @objc private func checkInput() {
        if cursor.isCaptured, let lastFrame, ProcessInfo.processInfo.systemUptime - lastFrame >= 0.5 {
            fail("Trackpad signal was lost; resume to retry")
        }
    }
    private func fail(_ message: String) {
        stop()
        failure = message
        paused = true
        updateMenu()
    }
    private func togglePause() {
        paused.toggle()
        if paused { failure = nil; stop(); updateMenu() } else { start() }
    }
    private func updateMenu() {
        menu?.update(failure ?? (!suspended.isEmpty ? "Session suspended" : (paused ? "Paused" : "Ready")), paused: paused)
    }
    @objc private func sessionChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: suspended.insert("sleep")
        case NSWorkspace.didWakeNotification: suspended.remove("sleep")
        case NSWorkspace.sessionDidResignActiveNotification: suspended.insert("session")
        case NSWorkspace.sessionDidBecomeActiveNotification: suspended.remove("session")
        case .init("com.apple.screenIsLocked"): suspended.insert("lock")
        case .init("com.apple.screenIsUnlocked"): suspended.remove("lock")
        default: return
        }
        start()
    }
}
