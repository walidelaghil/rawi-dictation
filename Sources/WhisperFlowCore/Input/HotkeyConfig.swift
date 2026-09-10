import CoreGraphics

public enum HotkeyMatcher: Equatable, Sendable {
    /// A bare modifier held down, e.g. fn or right-Option.
    case modifierFlag(CGEventFlags)
    /// A key plus modifiers, e.g. cmd+shift+d.
    case keyCode(UInt16, modifiers: CGEventFlags)
}

public enum HotkeyConfig {
    public static let escapeKeyCode: UInt16 = 53

    /// Bare modifiers usable on their own as a hold-to-talk key.
    static let bareModifiers: [String: CGEventFlags] = [
        "fn": .maskSecondaryFn,
        "function": .maskSecondaryFn,
        "rightoption": .maskAlternate,
        "rightalt": .maskAlternate,
        "rightcommand": .maskCommand,
        "rightcmd": .maskCommand,
        "rightcontrol": .maskControl,
        "rightctrl": .maskControl,
        "rightshift": .maskShift,
    ]

    static let modifierNames: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "ctrl": .maskControl, "control": .maskControl,
        "alt": .maskAlternate, "option": .maskAlternate, "opt": .maskAlternate,
        "fn": .maskSecondaryFn,
    ]

    /// ANSI virtual key codes.
    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46,
        "space": 49, "tab": 48, "return": 36, "enter": 36,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    public static func parse(_ raw: String) -> HotkeyMatcher? {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return nil }

        // A bare modifier, allowing "right option" as well as "rightOption".
        let squashed = lowered.replacingOccurrences(of: " ", with: "")
        if let flag = bareModifiers[squashed], !squashed.contains("+") {
            return .modifierFlag(flag)
        }

        let parts = squashed.split(separator: "+").map(String.init)
        guard parts.count >= 2, let last = parts.last,
              let code = keyCodes[last] else { return nil }

        var modifiers = CGEventFlags()
        for part in parts.dropLast() {
            guard let flag = modifierNames[part] else { return nil }
            modifiers.insert(flag)
        }
        guard !modifiers.isEmpty else { return nil }
        return .keyCode(code, modifiers: modifiers)
    }

    /// Human-readable form for the menu bar.
    public static func describe(_ raw: String) -> String {
        switch parse(raw) {
        case .modifierFlag(let f) where f == .maskSecondaryFn: "fn"
        case .none: raw
        default: raw
        }
    }
}
