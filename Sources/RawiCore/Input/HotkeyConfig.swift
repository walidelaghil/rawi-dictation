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
        "escape": 53, "esc": 53, "delete": 51, "backslash": 42, "slash": 44,
        "comma": 43, "period": 47, "semicolon": 41, "quote": 39, "grave": 50,
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

    /// Carbon can only bind a modifier+key combination, never a bare modifier.
    public static func isCarbonCompatible(_ raw: String) -> Bool {
        if case .keyCode = parse(raw) { return true }
        return false
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

// MARK: - Recording and display

public extension HotkeyConfig {
    /// The config-file spelling of a key press, or nil if it is not usable as a
    /// shortcut. Used by the settings screen: you press the combination you want
    /// and it writes the string, rather than you learning the vocabulary.
    static func string(keyCode: UInt16, modifiers: CGEventFlags) -> String? {
        guard let name = keyName(for: keyCode) else { return nil }
        // Caps lock and the "this came from the keypad" flag are states of the
        // keyboard, not part of a chord.
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("ctrl") }
        if modifiers.contains(.maskAlternate) { parts.append("option") }
        if modifiers.contains(.maskShift) { parts.append("shift") }
        if modifiers.contains(.maskCommand) { parts.append("cmd") }
        // A shortcut with no modifier would take that key away from every app.
        guard !parts.isEmpty else { return nil }
        return (parts + [name]).joined(separator: "+")
    }

    /// How macOS itself writes a shortcut: modifiers in the fixed order it uses,
    /// then the key.
    static func symbolic(_ raw: String) -> String {
        switch parse(raw) {
        case .modifierFlag(let flag):
            return bareModifierSymbol(flag) ?? raw
        case .keyCode(let code, let modifiers):
            var out = ""
            if modifiers.contains(.maskControl) { out += "⌃" }
            if modifiers.contains(.maskAlternate) { out += "⌥" }
            if modifiers.contains(.maskShift) { out += "⇧" }
            if modifiers.contains(.maskCommand) { out += "⌘" }
            return out + (keySymbol(for: code) ?? raw)
        case .none:
            // Never swallow it: a shortcut we cannot read is still the one the
            // user has, and showing nothing would look like it was unset.
            return raw
        }
    }

    /// The labels of any two shortcuts bound to the same combination.
    ///
    /// Two registrations of one chord means the second silently loses, so this is
    /// worth saying out loud before it is saved.
    static func clashes(in assignments: [(label: String, raw: String)]) -> [String] {
        var seen: [HotkeyMatcher: [String]] = [:]
        for assignment in assignments {
            guard let matcher = parse(assignment.raw) else { continue }
            seen[matcher, default: []].append(assignment.label)
        }
        return assignments
            .map(\.label)
            .filter { label in seen.values.contains { $0.count > 1 && $0.contains(label) } }
    }

    private static func keyName(for code: UInt16) -> String? {
        // The first spelling wins, so "escape" beats "esc" and "return" beats "enter".
        keyCodes.first { $0.value == code }.map(\.key).flatMap { _ in
            keyCodes.sorted { $0.key < $1.key }.first { $0.value == code }?.key
        }
    }

    private static func keySymbol(for code: UInt16) -> String? {
        let named: [UInt16: String] = [
            // "esc" rather than ⎋: the symbol is unreadable at 12pt, and the Mac
            // itself writes esc on the key.
            49: "Space", 48: "⇥", 36: "↩", 53: "esc", 51: "⌫",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let symbol = named[code] { return symbol }
        return keyName(for: code)?.uppercased()
    }

    private static func bareModifierSymbol(_ flag: CGEventFlags) -> String? {
        switch flag {
        case .maskSecondaryFn: "fn"
        case .maskAlternate: "⌥"
        case .maskCommand: "⌘"
        case .maskControl: "⌃"
        case .maskShift: "⇧"
        default: nil
        }
    }
}

extension HotkeyMatcher: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .modifierFlag(let flag):
            hasher.combine(0)
            hasher.combine(flag.rawValue)
        case .keyCode(let code, let modifiers):
            hasher.combine(1)
            hasher.combine(code)
            hasher.combine(modifiers.rawValue)
        }
    }
}
