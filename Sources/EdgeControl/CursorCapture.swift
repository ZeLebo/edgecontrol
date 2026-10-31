import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class CursorCapture {
    var onError: ((String) -> Void)?
    private(set) var isCaptured = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

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

    func stop() {
        release()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }

    isolated deinit { stop() }

    private func shouldDrop(type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            release()
            onError?("Cursor event interception was disabled")
            return false
        }
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

