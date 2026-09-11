import AppKit
import RawiCore

/// Owns the object graph and every timer. Deliberately the only place that knows
/// how the pieces are wired together, so each piece stays independently testable.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = FileLogger(alsoPrint: ProcessInfo.processInfo.environment["WF_DEBUG"] != nil)
    private let recorder = AudioRecorder()
    private let inserter: TextInserter
    private let pill = PillWindow()

    private var config = Config.default
    private var controller: DictationController!
    private var menuBar: MenuBarController!
    private var monitor: (any HotkeyBackend)?
    private var watcher: ConfigWatcher?
    private var tapPattern = TapPattern(doubleTapWindow: .milliseconds(350),
                                        minHold: .milliseconds(250))

    private var pendingTapTimer: Timer?
    private var pushToTalkSafetyTimer: Timer?
    private var sessionTimer: Timer?
    private var pillTimer: Timer?
    private var recordingStart: ContinuousClock.Instant?

    override init() {
        inserter = TextInserter()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        log.info("Rawi starting")

        Task { @MainActor in
            let (loaded, created) = await FirstRunSetup.loadOrCreate()
            self.config = loaded
            if created {
                self.log.info("""
                    First run: wrote \(Config.configFile.path) \
                    (engine=\(loaded.engine.rawValue), cleanup=\(loaded.cleanup.provider.rawValue))
                    """)
            }
            if self.config.needsModelDownload {
                self.log.warn("""
                    Transcription model missing: \(self.config.whispercpp.model). \
                    Download \(ModelStore.recommended.id) (\(ModelStore.recommended.approxSize)) \
                    to enable dictation.
                    """)
            }
            self.buildGraph()
            self.startMonitoring()
            self.startWatchingConfig()
            self.startRemoteTriggers()
            _ = await Permissions.requestMicrophone()
            self.logPermissions()
            self.menuBar.refresh(state: .idle, permissions: Permissions.current())
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        watcher?.stop()
        log.info("Rawi stopping")
    }

    /// Logged from inside the running app, because `--doctor` spawned from a
    /// terminal is attributed to that terminal by TCC and can under-report.
    private func logPermissions() {
        let p = Permissions.current()
        log.info("""
            Permissions — microphone: \(p.microphone), \
            inputMonitoring: \(p.inputMonitoring), accessibility: \(p.accessibility)
            """)
        if !p.allGranted {
            log.warn("Missing permissions: \(p.missing.joined(separator: ", "))")
        }
    }

    // MARK: - Graph

    private func buildGraph() {
        let env = DotEnv.load(from: Config.envFile)
        let engine = makeEngine(env: env)
        let cleanup = makeCleanup(env: env)

        if let routed = cleanup as? RoutedCleanup {
            log.info("Cleanup routed by script — latin: \(config.cleanup.models.latin), "
                     + "arabic: \(config.cleanup.models.arabic)")
            _ = routed
        }
        controller = DictationController(config: config, recorder: recorder, engine: engine,
                                         cleanup: cleanup, inserter: inserter, log: log)
        controller.onStateChange = { [weak self] state in
            self?.stateChanged(state)
        }
        menuBar = MenuBarController(controller: controller, log: log)
        tapPattern = TapPattern(doubleTapWindow: .milliseconds(config.doubleTapWindowMs),
                                minHold: .milliseconds(config.minHoldMs))
    }

    /// A misconfigured provider must not prevent the app from launching — it degrades
    /// to something that works and says so in the log and the menu bar.
    private func makeEngine(env: DotEnv) -> any TranscriptionEngine {
        do {
            return try TranscriptionEngineFactory.make(config: config, env: env)
        } catch {
            log.error("Falling back to local whisper: \(error.localizedDescription)")
            var fallback = config
            fallback.engine = .whispercpp
            return try! TranscriptionEngineFactory.make(config: fallback, env: env)
        }
    }

    private func makeCleanup(env: DotEnv) -> any CleanupProvider {
        do {
            return try CleanupProviderFactory.make(config: config, env: env)
        } catch {
            log.error("Cleanup disabled: \(error.localizedDescription)")
            return NoopCleanup()
        }
    }

    /// Debug/verification path — see `RemoteTrigger`. Drives exactly the same
    /// controller entry points the hotkey does.
    private func startRemoteTriggers() {
        RemoteTrigger.observe { action in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.log.info("Remote trigger: \(action.rawValue)")
                switch action {
                case .start: await self.controller.handle(.beganHold)
                case .handsFree: await self.controller.handle(.beganDoubleTap)
                case .stop: await self.controller.handle(.endedHold)
                case .cancel: await self.controller.cancelRequested()
                }
            }
        }
    }

    // MARK: - Input

    private func startMonitoring() {
        monitor?.stop()
        let granted = Permissions.current().inputMonitoring
        let backend = config.hotkeyBackend.resolved(inputMonitoringGranted: granted)

        do {
            switch backend {
            case .eventTap, .auto:
                try startEventTap()
            case .carbon:
                try startCarbon()
            }
            log.info("Hotkey: \(monitor?.describeBackend ?? "none")")
        } catch {
            log.error("Hotkey setup failed: \(error.localizedDescription)")
        }
    }

    private func startEventTap() throws {
        guard let matcher = HotkeyConfig.parse(config.hotkey) else {
            throw HotkeyError.carbonNeedsCombination(config.hotkey)
        }
        let monitor = HotkeyMonitor(
            matcher: matcher,
            onPress: { MainActor.assumeIsolated { self.feed(self.tapPattern.press(at: .now)) } },
            onRelease: { MainActor.assumeIsolated { self.feed(self.tapPattern.release(at: .now)) } },
            onEscape: { MainActor.assumeIsolated { self.escapePressed() } })
        try monitor.start()
        self.monitor = monitor
        log.info("Listening for \(config.hotkey) (listen-only tap)")
    }

    /// Used when Input Monitoring cannot be granted — on a managed Mac the user may
    /// not be a local admin at all. Carbon hotkeys need no permission, but cannot
    /// bind a bare modifier, so a combination is substituted and said out loud.
    private func startCarbon() throws {
        var hotkey = config.hotkey
        if !HotkeyConfig.isCarbonCompatible(hotkey) {
            log.warn("""
                “\(config.hotkey)” needs Input Monitoring, which is not granted. \
                Falling back to “\(config.fallbackHotkey)”, which needs no permission.
                """)
            hotkey = config.fallbackHotkey
        }
        guard case .keyCode(let code, let mods)? = HotkeyConfig.parse(hotkey) else {
            throw HotkeyError.carbonNeedsCombination(hotkey)
        }

        var cancelCode: UInt16?
        var cancelMods = CGEventFlags()
        if case .keyCode(let cc, let cm)? = HotkeyConfig.parse(config.cancelHotkey) {
            cancelCode = cc
            cancelMods = cm
        }

        let monitor = CarbonHotkeyMonitor(
            keyCode: code, modifiers: mods,
            cancelKeyCode: cancelCode, cancelModifiers: cancelMods,
            onPress: { MainActor.assumeIsolated { self.feed(self.tapPattern.press(at: .now)) } },
            onRelease: { MainActor.assumeIsolated { self.feed(self.tapPattern.release(at: .now)) } },
            onCancel: { MainActor.assumeIsolated { self.escapePressed() } })
        try monitor.start()
        self.monitor = monitor
        log.info("Listening for \(hotkey); cancel with \(config.cancelHotkey)")
    }

    private func feed(_ outcome: TapOutcome) {
        if outcome == .pendingShortTap { schedulePendingTapTimer() }
        if outcome == .beganDoubleTap || outcome == .beganHold { pendingTapTimer?.invalidate() }
        guard outcome != .ignored else { return }
        Task { @MainActor in await controller.handle(outcome) }
    }

    private func escapePressed() {
        guard controller.state.isBusy else { return }
        Task { @MainActor in await controller.cancelRequested() }
    }

    /// Fires after the double-tap window has definitely closed. Scheduling from the
    /// release rather than the first press is intentionally generous: firing late is
    /// harmless because `pendingExpired` ignores an already-promoted session, whereas
    /// firing early would swallow a valid double tap.
    private func schedulePendingTapTimer() {
        pendingTapTimer?.invalidate()
        let window = Double(config.doubleTapWindowMs) / 1000.0
        pendingTapTimer = Timer.scheduledTimer(withTimeInterval: window, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.feed(self.tapPattern.pendingExpired(at: .now))
            }
        }
    }

    // MARK: - State

    private func stateChanged(_ state: DictationState) {
        menuBar.refresh(state: state, permissions: Permissions.current())

        if state.recordingMode != nil {
            if recordingStart == nil { recordingStart = .now }
            startPillUpdates()
            if state.recordingMode == .handsFree {
                scheduleSessionTimeout()
            } else {
                schedulePushToTalkSafety()
            }
        } else if state.isBusy {
            pushToTalkSafetyTimer?.invalidate()
            startPillUpdates()
            sessionTimer?.invalidate()
        } else {
            recordingStart = nil
            sessionTimer?.invalidate()
            pushToTalkSafetyTimer?.invalidate()
            pillTimer?.invalidate()
            pillTimer = nil
            pill.hide()
        }
    }

    private func scheduleSessionTimeout() {
        guard sessionTimer == nil || !(sessionTimer?.isValid ?? false) else { return }
        let limit = Double(config.maxSessionSeconds)
        sessionTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.controller.sessionTimedOut()
            }
        }
    }

    /// A Carbon hotkey can miss its release event if the modifiers are lifted before
    /// the key, which would otherwise leave the mic recording indefinitely.
    private func schedulePushToTalkSafety() {
        pushToTalkSafetyTimer?.invalidate()
        let limit = Double(config.maxPushToTalkSeconds)
        pushToTalkSafetyTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.controller.state.recordingMode == .pushToTalk else { return }
                self.log.warn("Push-to-talk ran \(Int(limit))s with no key release; stopping")
                await self.controller.handle(.endedHold)
            }
        }
    }

    private func startPillUpdates() {
        guard pillTimer == nil || !(pillTimer?.isValid ?? false) else { return }
        updatePill()
        pillTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated { self.updatePill() }
        }
    }

    private func updatePill() {
        let state = controller.state
        let elapsed: Duration = recordingStart.map { $0.duration(to: .now) } ?? .zero
        var remaining: Duration?
        if state.recordingMode == .handsFree {
            let limit = Duration.seconds(config.maxSessionSeconds)
            remaining = limit - elapsed
        }
        pill.show(state: state, level: recorder.level, elapsed: elapsed, remaining: remaining)
    }

    // MARK: - Config reload

    private func startWatchingConfig() {
        watcher = ConfigWatcher { [weak self] in
            Task { @MainActor [weak self] in
                self?.reloadConfig()
            }
        }
        watcher?.start()
    }

    private func reloadConfig() {
        guard let reloaded = try? Config.load() else {
            log.warn("Config file is not valid JSON; keeping the previous settings")
            return
        }
        guard reloaded != config else { return }
        guard controller.state == .idle else { return }   // never swap mid-dictation

        let hotkeyChanged = reloaded.hotkey != config.hotkey
        config = reloaded
        let env = DotEnv.load(from: Config.envFile)
        controller.reconfigure(config: config,
                               engine: makeEngine(env: env),
                               cleanup: makeCleanup(env: env))
        tapPattern = TapPattern(doubleTapWindow: .milliseconds(config.doubleTapWindowMs),
                                minHold: .milliseconds(config.minHoldMs))
        if hotkeyChanged { startMonitoring() }
        log.info("Config reloaded (engine=\(config.engine.rawValue), "
                 + "cleanup=\(config.cleanup.provider.rawValue), hotkey=\(config.hotkey))")
    }
}
