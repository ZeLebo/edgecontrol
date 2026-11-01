import AppKit
import Testing
@testable import EdgeControl

@MainActor
struct KeyboardShortcutOutputTests {
    @Test func allExtendedFunctionKeysPreserveDistinctCharactersOnDownAndUpAfterSerialization() throws {
        for number in 21...24 {
            let shortcut = try #require(KeyboardShortcut.functionKey(number, modifiers: [.control, .command]))
            for down in [true, false] {
                let event = try CGKeyboardShortcutTransport.makeEvent(shortcut, keyDown: down,
                    flags: CGKeyboardShortcutTransport.flags(for: shortcut.modifiers), source: nil)
                let data = try #require(event.data)
                let restored = try #require(CGEvent(withDataAllocator: nil, data: data))
                let native = try #require(NSEvent(cgEvent: restored))
                #expect(native.keyCode == 0xff)
                #expect(native.characters?.unicodeScalars.map(\.value) == [UInt32(0xf703 + number)])
                #expect(native.charactersIgnoringModifiers == native.characters)
                #expect(native.modifierFlags.contains([.function, .control, .command]))
                #expect(native.type == (down ? .keyDown : .keyUp))
            }
        }
    }

    @Test func physicalFunctionKeysUseDocumentedCodesAndAllModifierCombinationsRoundTrip() throws {
        let expected: [UInt16] = [0x69, 0x6b, 0x71, 0x6a, 0x40, 0x4f, 0x50, 0x5a]
        for (index, code) in expected.enumerated() {
            let shortcut = try #require(KeyboardShortcut.functionKey(index + 13))
            #expect(shortcut.keyCode == code)
            #expect(shortcut.compatibilityNotice == nil)
            #expect(shortcut.displayName == "F\(index + 13)")
        }
        for raw in UInt8(0)...15 {
            let shortcut = KeyboardShortcut(keyCode: 0, modifiers: .init(rawValue: raw))
            let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut))
            #expect(decoded == shortcut)
            #expect(decoded.isValid)
        }
        #expect(KeyboardShortcut.functionKey(23)?.compatibilityNotice != nil)
        #expect(KeyboardShortcut.functionKey(0) == nil)
        #expect(KeyboardShortcut.functionKey(25) == nil)
    }

    @Test func keyUpPayloadRestoresHardwareFlags() throws {
        let shortcuts = [
            KeyboardShortcut(keyCode: 0),
            try #require(KeyboardShortcut.functionKey(13)),
            try #require(KeyboardShortcut.functionKey(23)),
        ]
        for shortcut in shortcuts {
            let down = try CGKeyboardShortcutTransport.makeEvent(shortcut, keyDown: true,
                flags: [.maskCommand, .maskAlternate, .maskControl], source: nil)
            let up = try CGKeyboardShortcutTransport.makeEvent(shortcut, keyDown: false,
                flags: [.maskShift], source: nil)
            let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            #expect(down.flags.intersection(modifiers) == [.maskCommand, .maskAlternate, .maskControl])
            #expect(up.flags.intersection(modifiers) == [.maskShift])
            if shortcut.extendedFunctionKey != nil {
                let data = try #require(up.data)
                let copy = try #require(CGEvent(withDataAllocator: nil, data: data))
                #expect(try #require(NSEvent(cgEvent: copy)).characters == String(UnicodeScalar(NSF23FunctionKey)!))
            }
        }
    }

    @Test func recorderKeysRemainValidWhileModifierOnlyAndMixedExtendedRepresentationsAreRejected() {
        for code in [UInt16(0), 36, 48, 49, 53, 76, 123, 126] {
            #expect(KeyboardShortcut(keyCode: code, modifiers: [.option, .shift]).isValid)
        }
        for code in UInt16(54)...63 { #expect(KeyboardShortcut(keyCode: code).isValid == false) }
        #expect(KeyboardShortcut(keyCode: 128).isValid == false)
        #expect(KeyboardShortcut(keyCode: 255).isValid == false)
        #expect(KeyboardShortcut(keyCode: 0, extendedFunctionKey: 23).isValid == false)
        #expect(KeyboardShortcut(keyCode: 255, extendedFunctionKey: 20).isValid == false)
        #expect(KeyboardShortcut(keyCode: 0, modifiers: .init(rawValue: 16)).isValid == false)
    }

    @Test func sendsOneDownThenOneUpAfterSeventyFiveMillisecondsAndDeduplicatesWhileHeld() throws {
        let hardware = RecordingTransport()
        let clock = FakeScheduler()
        let output = KeyboardShortcutOutput(transport: hardware, scheduler: clock)
        let shortcut = try #require(KeyboardShortcut.functionKey(13, modifiers: [.command]))
        #expect(try output.send(shortcut))
        #expect(try output.send(shortcut) == false)
        #expect(hardware.requests.map(\.down) == [true])
        #expect(output.isBusy)
        clock.advance(to: 0.074)
        #expect(hardware.requests.count == 1)
        clock.advance(to: 0.075)
        #expect(hardware.requests.map(\.down) == [true, false])
        #expect(output.isBusy == false)
        #expect(try output.send(shortcut))
        #expect(hardware.requests.count == 3)
    }

    @Test func otherKeysDoNotQueueAndCancelReleasesOnlyTheOwnedKey() throws {
        let hardware = RecordingTransport()
        let clock = FakeScheduler()
        let output = KeyboardShortcutOutput(transport: hardware, scheduler: clock)
        let first = try #require(KeyboardShortcut.functionKey(13))
        let second = try #require(KeyboardShortcut.functionKey(14))
        try output.send(first)
        #expect(throws: KeyboardShortcutError.self) { try output.send(second) }
        output.cancel()
        output.cancel()
        try output.send(second)
        clock.fireCancelledCallbacks()
        #expect(hardware.requests.map(\.shortcut) == [first, first, second])
        #expect(hardware.requests.map(\.down) == [true, false, true])
        clock.advance(to: 0.075)
        #expect(hardware.requests.map(\.down) == [true, false, true, false])
    }

    @Test func failedDownIsVisibleAndFailedUpRetainsOwnershipForAnExplicitRetry() throws {
        let hardware = RecordingTransport()
        let clock = FakeScheduler()
        let output = KeyboardShortcutOutput(transport: hardware, scheduler: clock)
        let shortcut = try #require(KeyboardShortcut.functionKey(24))
        #expect(throws: KeyboardShortcutError.self) { try output.send(KeyboardShortcut(keyCode: 255)) }
        #expect(hardware.requests.isEmpty)
        hardware.failDown = true
        #expect(throws: PostFailure.self) { try output.send(shortcut) }
        #expect(output.isBusy == false)
        #expect(clock.jobs.isEmpty)
        hardware.failDown = false
        try output.send(shortcut)
        hardware.failUp = true
        var errors: [String] = []
        output.onError = { errors.append($0) }
        clock.advance(to: 0.075)
        #expect(errors.count == 1)
        #expect(output.isBusy)
        hardware.failUp = false
        output.cancel()
        #expect(output.isBusy == false)
        #expect(hardware.requests.map(\.down) == [true, true, false, false])
    }

    private enum PostFailure: Error { case requested }

    private final class RecordingTransport: KeyboardShortcutTransport {
        struct Request { let shortcut: KeyboardShortcut; let down: Bool }
        var requests: [Request] = []
        var failDown = false
        var failUp = false
        func post(_ shortcut: KeyboardShortcut, keyDown: Bool) throws {
            requests.append(Request(shortcut: shortcut, down: keyDown))
            if (keyDown && failDown) || (!keyDown && failUp) { throw PostFailure.requested }
        }
    }

    private final class FakeScheduler: KeyboardShortcutScheduler {
        final class Job: KeyboardShortcutCancellation {
            let deadline: TimeInterval
            let action: @MainActor @Sendable () -> Void
            var cancelled = false
            init(deadline: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) {
                self.deadline = deadline
                self.action = action
            }
            func cancel() { cancelled = true }
        }
        var time = 0.0
        var jobs: [Job] = []
        func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) -> any KeyboardShortcutCancellation {
            let job = Job(deadline: time + delay, action: action)
            jobs.append(job)
            return job
        }
        func advance(to time: TimeInterval) {
            self.time = time
            let due = jobs.filter { !$0.cancelled && $0.deadline <= time }
            for job in due { job.cancel(); job.action() }
        }
        func fireCancelledCallbacks() {
            for job in jobs where job.cancelled { job.action() }
        }
    }
}
