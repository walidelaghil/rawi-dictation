import AppKit
import ServiceManagement

/// The status-bar item: the only always-visible surface, since the app has no Dock
/// icon and no settings window.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let controller: DictationController
    private let log: any Logging

    private var permissions: PermissionStatus = Permissions.current()
    private var state: DictationState = .idle

    public var onQuit: (() -> Void)?

    public init(controller: DictationController, log: any Logging) {
        self.controller = controller
        self.log = log
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh(state: .idle, permissions: Permissions.current())
    }

    public func refresh(state: DictationState, permissions: PermissionStatus) {
        self.state = state
        self.permissions = permissions

        guard let button = statusItem.button else { return }
        let name: String
        if !controller.isEnabled {
            name = "mic.slash"
        } else if !permissions.allGranted {
            name = "exclamationmark.triangle"
        } else if state.recordingMode != nil {
            name = "mic.fill"
        } else if state.isBusy {
            name = "waveform"
        } else {
            name = "mic"
        }
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "WhisperFlow")
        button.image?.isTemplate = true
        button.toolTip = "WhisperFlow — \(PillLabel.text(for: state))"
    }

    /// Rebuilt on open so permission rows and the login-item checkbox are current.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        permissions = Permissions.current()
        menu.removeAllItems()

        let status = NSMenuItem(title: "WhisperFlow — \(PillLabel.text(for: state))",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let hotkey = NSMenuItem(
            title: "Hotkey: \(controller.currentConfig.hotkey)  ·  hold to talk, double-tap for hands-free",
            action: nil, keyEquivalent: "")
        hotkey.isEnabled = false
        menu.addItem(hotkey)

        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled),
                                 keyEquivalent: "")
        enabled.target = self
        enabled.state = controller.isEnabled ? .on : .off
        menu.addItem(enabled)

        if !permissions.allGranted {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Permissions needed", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for pane in Permissions.SettingsPane.allCases where isMissing(pane) {
                let item = NSMenuItem(title: "  Grant \(pane.title) — \(pane.rationale)",
                                      action: #selector(openPane(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pane.rawValue
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem),
                               keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let config = NSMenuItem(title: "Open Config File…", action: #selector(openConfig),
                                keyEquivalent: "")
        config.target = self
        menu.addItem(config)

        let logs = NSMenuItem(title: "Reveal Logs…", action: #selector(revealLogs),
                              keyEquivalent: "")
        logs.target = self
        menu.addItem(logs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit WhisperFlow", action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func isMissing(_ pane: Permissions.SettingsPane) -> Bool {
        switch pane {
        case .accessibility: !permissions.accessibility
        case .inputMonitoring: !permissions.inputMonitoring
        case .microphone: !permissions.microphone
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
        log.info("Dictation \(controller.isEnabled ? "enabled" : "disabled")")
        refresh(state: state, permissions: permissions)
    }

    @objc private func openPane(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pane = Permissions.SettingsPane(rawValue: raw) else { return }
        if pane == .accessibility { Permissions.requestAccessibilityPrompt() }
        Permissions.openSettings(for: pane)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                log.info("Launch at login disabled")
            } else {
                try SMAppService.mainApp.register()
                log.info("Launch at login enabled")
            }
        } catch {
            log.error("Could not change login item: \(error.localizedDescription)")
        }
    }

    @objc private func openConfig() {
        let url = Config.configFile
        if !FileManager.default.fileExists(atPath: url.path) {
            try? controller.currentConfig.save(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealLogs() {
        NSWorkspace.shared.selectFile(FileLogger.defaultURL.path,
                                      inFileViewerRootedAtPath: FileLogger.defaultURL
                                          .deletingLastPathComponent().path)
    }

    @objc private func quit() {
        onQuit?()
        NSApp.terminate(nil)
    }
}
