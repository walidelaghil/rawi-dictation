import AppKit
import ServiceManagement
import SwiftUI

/// The status item and its dropdown.
///
/// The dropdown is a SwiftUI panel in an `NSPopover` rather than an `NSMenu`,
/// because the design is a custom surface — a live state block, an action strip
/// and a disclosure — none of which an `NSMenu` can express. The utility items
/// that would clutter that panel live behind the gear instead.
@MainActor
public final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let controller: DictationController
    private let log: any Logging

    private let panel = MenuPanelModel()
    private let popover = NSPopover()

    private var permissions: PermissionStatus = Permissions.current()
    private var state: DictationState = .idle

    public var onAction: ((String) -> Void)?
    public var onAppearanceChange: ((Appearance) -> Void)?
    public var onQuit: (() -> Void)?
    public var onOpenWindow: (() -> Void)?

    public init(controller: DictationController, log: any Logging) {
        self.controller = controller
        self.log = log
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: MenuPanelView(model: panel))
        // Let SwiftUI drive the popover's size. Without this the popover opens at
        // the hosting controller's un-laid-out size, anchors its *bottom* there,
        // and then shrinks to fit — which left the panel hanging 148 points below
        // the menu bar instead of under the status item. Measured, not guessed:
        // the item sat at y=1050 and the panel's top landed at 902.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        panel.onAction = { [weak self] id in
            self?.popover.performClose(nil)
            self?.onAction?(id)
        }
        panel.onCopy = { [weak self] item in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.text, forType: .string)
            self?.log.info("Re-copied a recent dictation")
        }
        panel.onSettings = { [weak self] in self?.showSettingsMenu() }
        panel.onOpenWindow = { [weak self] in
            self?.popover.performClose(nil)
            self?.onOpenWindow?()
        }
        panel.onQuit = { [weak self] in
            self?.onQuit?()
            NSApp.terminate(nil)
        }

        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
        refresh(state: .idle, permissions: Permissions.current())
    }

    // MARK: - Live state

    public func refresh(state: DictationState, permissions: PermissionStatus) {
        self.state = state
        self.permissions = permissions
        panel.state = state

        guard let button = statusItem.button else { return }
        // The Rawi mark, not an SF Symbol: the menu bar is where this app lives, so
        // it should be recognisable there rather than borrowing a generic mic. State
        // rides on colour instead of on a different glyph — see RawiMark.
        button.image = RawiMark.statusImage(state: state, enabled: controller.isEnabled,
                                            microphoneGranted: permissions.microphone)
        button.toolTip = "Rawi — \(PillLabel.text(for: state))"
    }

    public func updateLive(level: Double, elapsed: Duration, detectedLanguage: String?) {
        panel.level = level
        panel.elapsed = elapsed
        panel.detectedLanguage = detectedLanguage
    }

    public func setRecent(_ recent: [RecentDictation]) { panel.recent = recent }

    public func setAppearance(_ appearance: ResolvedAppearance) { panel.appearance = appearance }

    // MARK: - Popover

    /// Same entry point as clicking the status item.
    public func togglePanel() { togglePopover() }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            permissions = Permissions.current()
            // Measure before showing: a popover positions itself from the size it
            // has at that moment, and a SwiftUI view that has never been laid out
            // reports the wrong one.
            if let view = popover.contentViewController?.view {
                view.layoutSubtreeIfNeeded()
                let fitting = view.fittingSize
                if fitting.width > 0, fitting.height > 0 { popover.contentSize = fitting }
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            logAnchor(button)
        }
    }

    /// Where macOS actually put the status item, and where the panel landed.
    ///
    /// The popover is anchored to the button and nothing else, so when it opens far
    /// from the menu bar the cause is outside this code — the item pushed into an
    /// overflow, or sitting on another screen. Guessing at that from a screenshot
    /// wastes a round trip; these three rectangles settle it.
    private func logAnchor(_ button: NSStatusBarButton) {
        func describe(_ rect: NSRect) -> String {
            String(format: "%.0f,%.0f %.0fx%.0f",
                   rect.origin.x, rect.origin.y, rect.width, rect.height)
        }
        let item = button.window?.frame ?? .zero
        let screen = button.window?.screen ?? NSScreen.main
        log.info("""
            Menu panel — item \(describe(item)),             panel \(describe(popover.contentViewController?.view.window?.frame ?? .zero)),             screen \(describe(screen?.frame ?? .zero))             visible \(describe(screen?.visibleFrame ?? .zero)),             screens \(NSScreen.screens.count)
            """)
    }

    // MARK: - Settings, behind the gear so the panel stays as designed

    private func showSettingsMenu() {
        let menu = NSMenu()

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = controller.isEnabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(.separator())
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for option in Appearance.allCases {
            let item = NSMenuItem(title: option.displayName,
                                  action: #selector(pickAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = controller.currentConfig.appearance == option ? .on : .off
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        if !permissions.allGranted {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
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

        for (title, selector) in [("Open Config File…", #selector(openConfig)),
                                  ("Reveal Logs…", #selector(revealLogs))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        if let button = statusItem.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
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

    @objc private func pickAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let appearance = Appearance(rawValue: raw) else { return }
        log.info("Appearance set to \(appearance.rawValue)")
        onAppearanceChange?(appearance)
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
}
