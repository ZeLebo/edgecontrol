import AppKit
import CoreGraphics

@MainActor
protocol KeyboardShortcutTransport: AnyObject {
    func post(_ shortcut: KeyboardShortcut, keyDown: Bool) throws
}

@MainActor
protocol KeyboardShortcutCancellation: AnyObject { func cancel() }

@MainActor
protocol KeyboardShortcutScheduler: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) -> any KeyboardShortcutCancellation
}

@MainActor
final class KeyboardShortcutOutput {
    var onError: ((String) -> Void)?
    private let transport: any KeyboardShortcutTransport
    private let scheduler: any KeyboardShortcutScheduler
    private var held: KeyboardShortcut?
    private var releaseTimer: (any KeyboardShortcutCancellation)?
    private var generation = 0
    var isBusy: Bool { held != nil }

    init(transport: (any KeyboardShortcutTransport)? = nil, scheduler: (any KeyboardShortcutScheduler)? = nil) {
        self.transport = transport ?? CGKeyboardShortcutTransport()
        self.scheduler = scheduler ?? RunLoopShortcutScheduler()
    }

    @discardableResult
    func send(_ shortcut: KeyboardShortcut) throws -> Bool {
        guard shortcut.isValid else { throw KeyboardShortcutError.invalidShortcut }
        if held == shortcut { return false }
        guard held == nil else { throw KeyboardShortcutError.busy }
        try transport.post(shortcut, keyDown: true)
        held = shortcut
        generation &+= 1
        let expected = generation
        releaseTimer = scheduler.schedule(after: 0.075) { [weak self] in
            guard let self, self.generation == expected else { return }
            self.cancel()
        }
        return true
    }

    func cancel() {
        generation &+= 1
        releaseTimer?.cancel()
        releaseTimer = nil
        guard let held else { return }
        do {
            try transport.post(held, keyDown: false)
            self.held = nil
        } catch {
            // Keep ownership so a later cancel can retry the matching release.
            if let onError { onError(error.localizedDescription) }
            else { NSLog("EdgeControl shortcut: %@", error.localizedDescription) }
        }
    }

    isolated deinit { cancel() }
}

enum KeyboardShortcutError: LocalizedError {
    case invalidShortcut, busy, permission, eventCreation, keyAlreadyPressed
    var errorDescription: String? {
        switch self {
        case .invalidShortcut: "The keyboard shortcut is invalid"
        case .busy: "Another keyboard shortcut is still being released"
        case .permission: "Accessibility permission is required to send keyboard shortcuts"
        case .eventCreation: "Could not create the keyboard shortcut event"
        case .keyAlreadyPressed: "The shortcut key is already held on the keyboard"
        }
    }
}

@MainActor
final class CGKeyboardShortcutTransport: KeyboardShortcutTransport {
    private var source: CGEventSource?

    func post(_ shortcut: KeyboardShortcut, keyDown: Bool) throws {
        if keyDown {
            guard CGPreflightPostEventAccess() else { throw KeyboardShortcutError.permission }
            if shortcut.extendedFunctionKey == nil,
               CGEventSource.keyState(.hidSystemState, key: shortcut.keyCode) {
                throw KeyboardShortcutError.keyAlreadyPressed
            }
        }
        if source == nil { source = CGEventSource(stateID: .privateState) }
        guard let source else { throw KeyboardShortcutError.eventCreation }
        // Do not synthesize modifier-key presses or release physically held
        // modifiers. Restore the hardware flags on the matching main-key up.
        let flags = keyDown ? Self.flags(for: shortcut.modifiers) : CGEventSource.flagsState(.hidSystemState)
        let event = try Self.makeEvent(shortcut, keyDown: keyDown, flags: flags, source: source)
        // CGEventPost has no delivery acknowledgement. Key-up is still attempted
        // if posting permission changed after an accepted key-down.
        event.post(tap: .cghidEventTap)
    }

    // Build-only seam: tests inspect/serialize real events without posting them.
    static func makeEvent(_ shortcut: KeyboardShortcut, keyDown: Bool,
                          flags: CGEventFlags, source: CGEventSource?) throws -> CGEvent {
        guard shortcut.isValid else { throw KeyboardShortcutError.invalidShortcut }
        var eventFlags = flags
        if shortcut.functionNumber != nil { eventFlags.insert(.maskSecondaryFn) }
        if let number = shortcut.extendedFunctionKey {
            // Apple maps HID F21–F24 to DEADKEY (0xff), not a physical CG code:
            // https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDFamily/Cosmo_USB2ADB.c#L143
            // AppKit explicitly supports their characters in keyEvent:
            // https://developer.apple.com/documentation/appkit/function-key-unicode-values
            let text = String(UnicodeScalar(0xf703 + number)!)
            guard let native = NSEvent.keyEvent(
                with: keyDown ? .keyDown : .keyUp, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(eventFlags.rawValue)),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0xff
            ), let event = native.cgEvent else { throw KeyboardShortcutError.eventCreation }
            if let source { event.setSource(source) }
            return event
        }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown) else {
            throw KeyboardShortcutError.eventCreation
        }
        event.flags = eventFlags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        return event
    }

    static func flags(for modifiers: ShortcutModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

@MainActor
private final class RunLoopShortcutScheduler: KeyboardShortcutScheduler {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) -> any KeyboardShortcutCancellation {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { action() } }
        RunLoop.main.add(timer, forMode: .common)
        return TimerCancellation(timer)
    }
}

@MainActor
private final class TimerCancellation: KeyboardShortcutCancellation {
    private let timer: Timer
    init(_ timer: Timer) { self.timer = timer }
    func cancel() { timer.invalidate() }
}
