import AppKit
import Testing
@testable import EdgeControl

@MainActor
struct ShortcutEditorCaptureTests {
    @Test func keepsThePhysicalKeyAndOnlyTheFourSupportedModifiers() throws {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .capsLock, .function, .numericPad]
        let captured = shortcut(from: try event(keyCode: 12, flags: flags, characters: "q"))
        #expect(captured == KeyboardShortcut(keyCode: 12, modifiers: [.command, .option, .control, .shift]))
        #expect(captured?.displayName == "⌃⌥⇧⌘Q")
    }

    @Test func keyCaptureDoesNotDependOnTheTypedKeyboardLayoutCharacter() throws {
        let captured = shortcut(from: try event(keyCode: 0, flags: .option, characters: "å"))
        #expect(captured == KeyboardShortcut(keyCode: 0, modifiers: .option))
    }

    @Test func mapsExtendedFunctionCharactersToF21ThroughF24() throws {
        for number in 21...24 {
            let scalar = try #require(UnicodeScalar(0xF718 + number - 21))
            let captured = shortcut(from: try event(keyCode: 255, flags: [.command, .shift], characters: String(scalar)))
            #expect(captured == KeyboardShortcut.functionKey(number, modifiers: [.command, .shift]))
            #expect(captured?.compatibilityNotice != nil)
        }
    }

    @Test func capturesPhysicalF13ThroughF20WithoutUsingExtendedEvents() throws {
        for number in 13...20 {
            let initial = try #require(KeyboardShortcut.functionKey(number, modifiers: .control))
            let scalar = try #require(UnicodeScalar(0xF704 + number - 1))
            let captured = shortcut(from: try event(keyCode: initial.keyCode, flags: .control, characters: String(scalar)))
            #expect(captured == initial)
            #expect(captured?.extendedFunctionKey == nil)
        }
    }

    @Test func ignoresModifierOnlyKeysAndKeyUpEvents() throws {
        for keyCode in UInt16(54)...63 {
            #expect(shortcut(from: try event(keyCode: keyCode, flags: .command, characters: "")) == nil)
        }
        #expect(shortcut(from: try event(type: .keyUp, keyCode: 12, flags: .command, characters: "q")) == nil)
    }

    @Test func invalidPhysicalCodesAreNotCapturedWithoutAFunctionCharacter() throws {
        for keyCode in [UInt16(128), 255, 65535] {
            #expect(shortcut(from: try event(keyCode: keyCode, characters: "")) == nil)
        }
    }

    @Test func preservesCommandCombinationsAndModifiedEscapeAsRecordableValues() throws {
        #expect(shortcut(from: try event(keyCode: 12, flags: .command, characters: "q")) == KeyboardShortcut(keyCode: 12, modifiers: .command))
        #expect(shortcut(from: try event(keyCode: 53, flags: .option, characters: "\u{1b}")) == KeyboardShortcut(keyCode: 53, modifiers: .option))
    }

    private func event(type: NSEvent.EventType = .keyDown, keyCode: UInt16,
                       flags: NSEvent.ModifierFlags = [], characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 1,
                                     windowNumber: 0, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }
}
