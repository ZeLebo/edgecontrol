import Foundation

struct ShortcutModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }
    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    var modifiers: ShortcutModifiers
    let extendedFunctionKey: Int?

    init(keyCode: UInt16, modifiers: ShortcutModifiers = [], extendedFunctionKey: Int? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.extendedFunctionKey = extendedFunctionKey
    }

    var isValid: Bool {
        guard modifiers.rawValue & 0xf0 == 0 else { return false }
        if let extendedFunctionKey {
            return keyCode == 0xff && (21...24).contains(extendedFunctionKey)
        }
        return keyCode < 128 && !(54...63).contains(keyCode)
    }

    static func functionKey(_ number: Int, modifiers: ShortcutModifiers = []) -> Self? {
        if (1...20).contains(number) {
            return Self(keyCode: functionCodes[number - 1], modifiers: modifiers)
        }
        guard (21...24).contains(number) else { return nil }
        return Self(keyCode: 0xff, modifiers: modifiers, extendedFunctionKey: number)
    }

    var compatibilityNotice: String? {
        guard extendedFunctionKey != nil else { return nil }
        return "F21–F24 use function-character events. Some apps and global hotkey tools do not recognize them."
    }

    var displayName: String {
        let prefix = [(ShortcutModifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }.map(\.1).joined()
        if let number = functionNumber { return prefix + "F\(number)" }
        return prefix + (Self.keyNames[keyCode] ?? String(format: "Key 0x%02X", keyCode))
    }

    var functionNumber: Int? {
        if let extendedFunctionKey { return extendedFunctionKey }
        return Self.functionCodes.firstIndex(of: keyCode).map { $0 + 1 }
    }

    // Carbon/HIToolbox Events.h virtual codes, not USB HID usages.
    private static let functionCodes: [UInt16] = [
        0x7a, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6d,
        0x67, 0x6f, 0x69, 0x6b, 0x71, 0x6a, 0x40, 0x4f, 0x50, 0x5a,
    ]
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Escape", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +",
        71: "Clear", 75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
        110: "Menu", 114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
