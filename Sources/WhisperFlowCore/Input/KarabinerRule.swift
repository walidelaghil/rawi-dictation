import Foundation

/// Generates a Karabiner-Elements complex-modification that drives WhisperFlow.
///
/// Why this exists: on a managed Mac the user may not be a local admin, so Input
/// Monitoring cannot be granted and a bare `fn` cannot be observed. Karabiner is
/// commonly already installed *and* already granted Input Monitoring by the admin,
/// and it can run a shell command on key down and key up. That borrowed permission
/// is what makes `fn` usable again.
///
/// The file is written to Karabiner's assets folder, which only makes the rule
/// *available* in Karabiner's UI. Nothing is enabled and no existing configuration
/// is touched — the user turns it on themselves.
public enum KarabinerRule {
    public static var assetsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/karabiner/assets/complex_modifications",
                                    isDirectory: true)
    }

    public static var ruleFile: URL {
        assetsDirectory.appendingPathComponent("whisperflow.json")
    }

    public static var isKarabinerInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Karabiner-Elements.app")
    }

    public static func json(executable: String) -> String {
        let cmd = { (action: String) in "'\(executable)' --trigger \(action)" }
        let rules: [[String: Any]] = [
            [
                "description": "WhisperFlow: hold fn to dictate (fn keeps working normally)",
                "manipulators": [[
                    "type": "basic",
                    "from": ["key_code": "fn", "modifiers": ["optional": ["any"]]],
                    // fn is re-sent first so it still works as a modifier for
                    // fn+arrows and the function-key row.
                    "to": [["key_code": "fn"], ["shell_command": cmd("start")]],
                    "to_after_key_up": [["shell_command": cmd("stop")]],
                ]],
            ],
            [
                "description": "WhisperFlow: hold right-command to dictate",
                "manipulators": [[
                    "type": "basic",
                    "from": ["key_code": "right_command", "modifiers": ["optional": ["any"]]],
                    "to": [["key_code": "right_command"], ["shell_command": cmd("start")]],
                    "to_after_key_up": [["shell_command": cmd("stop")]],
                ]],
            ],
            [
                "description": "WhisperFlow: Esc cancels dictation (Esc still reaches your app)",
                "manipulators": [[
                    "type": "basic",
                    "from": ["key_code": "escape", "modifiers": ["optional": ["any"]]],
                    "to": [["key_code": "escape"], ["shell_command": cmd("cancel")]],
                ]],
            ],
        ]

        let root: [String: Any] = ["title": "WhisperFlow Dictation", "rules": rules]
        let data = try! JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// Returns the path written to.
    @discardableResult
    public static func install(executable: String) throws -> URL {
        try FileManager.default.createDirectory(at: assetsDirectory,
                                                withIntermediateDirectories: true)
        try Data(json(executable: executable).utf8).write(to: ruleFile, options: .atomic)
        return ruleFile
    }
}
