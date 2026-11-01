import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class CursorCapture {
    var onError: ((String) -> Void)?
    private(set) var isCaptured = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clickFilter = CursorClickFilter()

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() throws {
        guard tap == nil else { return }
        guard Self.hasPermission else { throw CursorCaptureError.permission }
        let eventTypes: [CGEventType] = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp,
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let shouldDrop = MainActor.assumeIsolated {
                    let owner = Unmanaged<CursorCapture>.fromOpaque(context).takeUnretainedValue()
                    return owner.shouldDrop(type: type)
                }
                return shouldDrop ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw CursorCaptureError.unavailable }
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            throw CursorCaptureError.unavailable
        }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
    }

    func acquire() throws {
        guard let tap, CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) else {
            release()
            throw CursorCaptureError.unavailable
        }
        guard Self.hasPermission else {
            release()
            throw CursorCaptureError.permission
        }
        guard ![CGMouseButton.left, .right, .center].contains(where: {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }) else { throw CursorCaptureError.buttonDown }
        isCaptured = true
    }

    func release() { isCaptured = false }

    func setClickSuppression(_ enabled: Bool) { clickFilter.setSuppression(enabled) }

    func releaseAll() {
        release()
        clickFilter.setSuppression(false)
    }

    func stop() {
        releaseAll()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        clickFilter.reset()
    }

    isolated deinit { stop() }

    private func shouldDrop(type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseAll()
            onError?("Cursor event interception was disabled")
            return false
        }
        if type == .leftMouseDown || type == .leftMouseUp { return clickFilter.shouldDrop(type) }
        // Runtime acceptance must confirm that dropping session motion also freezes the physical cursor.
        return isCaptured
    }
}

private enum CursorCaptureError: LocalizedError {
    case permission
    case unavailable
    case buttonDown

    var errorDescription: String? {
        switch self {
        case .permission: "Accessibility permission is required"
        case .unavailable: "Cursor event interception is unavailable"
        case .buttonDown: "Release the mouse button before adjusting a level"
        }
    }
}

struct CursorClickFilter {
    private var suppressionRequested = false
    private var blockedLeftDown = false

    mutating func setSuppression(_ enabled: Bool) { suppressionRequested = enabled }

    mutating func shouldDrop(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown:
            if suppressionRequested || blockedLeftDown {
                blockedLeftDown = true
                return true
            }
            return false
        case .leftMouseUp:
            guard blockedLeftDown else { return false }
            blockedLeftDown = false
            return true
        default: return false
        }
    }

    mutating func reset() {
        suppressionRequested = false
        blockedLeftDown = false
    }
}

struct TapClickSuppression {
    private var tapDeadline: Double?
    private var profileDeadline: Double?

    mutating func update(_ tap: TapUpdate, at now: Double) -> Bool {
        tapDeadline = tap.suppressClicks ? valid(tap.suppressionUntil, at: now) : nil
        return advance(to: now)
    }
    mutating func preserveProfileTail(until deadline: Double?, at now: Double) -> Bool {
        // A new recognizer's inactive frames must not erase the preceding profile tap's tail.
        profileDeadline = valid(deadline, at: now).map { min($0, now + 0.08) }
        return advance(to: now)
    }
    mutating func advance(to now: Double) -> Bool {
        tapDeadline = valid(tapDeadline, at: now)
        profileDeadline = valid(profileDeadline, at: now)
        return tapDeadline != nil || profileDeadline != nil
    }
    mutating func reset() { tapDeadline = nil; profileDeadline = nil }
    private func valid(_ deadline: Double?, at now: Double) -> Double? {
        guard now.isFinite, let deadline, deadline.isFinite, deadline > now else { return nil }
        return deadline
    }
}
