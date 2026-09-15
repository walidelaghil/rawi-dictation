import Foundation

/// The shortcuts as the app should print them, resolved once from the config and
/// the permission state.
///
/// Five files used to hold their own glyph literals — "⌥Space" in the panel, in
/// the pill, in the History empty state, in the Transforms header, in the menu
/// actions — so rebinding a key changed the key and nothing else. Every one of
/// them was also wrong by default on the Mac this app was built for, where the
/// Carbon backend binds the fallback rather than the bare `fn`.
public struct HotkeyLabels: Sendable, Equatable {
    public let dictate: String
    public let transform: String
    public let cancel: String
    public let command: String

    public init(config: Config, inputMonitoringGranted: Bool) {
        dictate = HotkeyConfig.symbolic(
            config.effectiveDictateHotkey(inputMonitoringGranted: inputMonitoringGranted))
        transform = HotkeyConfig.symbolic(config.transformHotkey)
        cancel = HotkeyConfig.symbolic(config.cancelHotkey)
        command = HotkeyConfig.symbolic(config.commandHotkey)
    }

    init(dictate: String, transform: String, cancel: String, command: String = "⌃⌥C") {
        self.dictate = dictate
        self.transform = transform
        self.cancel = cancel
        self.command = command
    }

    /// Used before the graph is built, and by previews.
    public static let placeholder = HotkeyLabels(config: .default, inputMonitoringGranted: false)
}
