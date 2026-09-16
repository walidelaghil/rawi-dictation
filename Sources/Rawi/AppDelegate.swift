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
    private var setupWindow: SetupWindow?
    private var checklistWasComplete = true
    private var checklistTimer: Timer?
    /// Where launch time goes, logged once.
    private var launchMarks: [String] = []
    private let focusProbe = SystemFocusProbe()
    private var history: HistoryStore!
    private var vocabulary: VocabularyStore!
    private var commands: CommandStore!
    private var destinations: DestinationStore!
    private var transforms: TransformStore!
    private var mainWindow: MainWindow!

    private var config = Config.default
    private var controller: DictationController!
    private var menuBar: MenuBarController!
    private var monitor: (any HotkeyBackend)?
    /// Separate from `monitor` because the transform key is always Carbon, whichever
    /// backend dictation uses — Carbon needs no permission, and the transform key
    /// should not be the one feature that depends on one.
    private var transformMonitor: CarbonHotkeyMonitor?
    /// What dictation actually bound to, which is not always `config.hotkey` — the
    /// Carbon path substitutes the fallback. Needed to spot a clash.
    private var activeDictateKey: HotkeyMatcher?
    /// True when the Carbon monitor took the transform key too, so it does not also
    /// get its own.
    private var carbonCarriesTransform = false
    private var watcher: ConfigWatcher?
    private var tapPattern = TapPattern(doubleTapWindow: .milliseconds(350),
                                        minHold: .milliseconds(250))
    /// Its own pattern: a transform hold must not be read as the second tap of a
    /// dictation, and vice versa.
    private var commandMonitor: CarbonHotkeyMonitor?
    private var commandTapPattern = TapPattern(doubleTapWindow: .milliseconds(350),
                                               minHold: .milliseconds(250))
    private var transformTapPattern = TapPattern(doubleTapWindow: .milliseconds(350),
                                                 minHold: .milliseconds(250))

    private var pendingTapTimer: Timer?
    private var pushToTalkSafetyTimer: Timer?
    private var sessionTimer: Timer?
    private var pillTimer: Timer?
    private var recordingStart: ContinuousClock.Instant?
    /// One timeline for the mark, shared by the menu bar, the pill and the panel.
    /// Three separate animations would drift apart within a second.
    private var markMotion = MarkMotion.rest
    private var meter = MeterBallistics()
    private var stateEnteredAt = Date()
    private var lastFrameAt = Date()

    override init() {
        inserter = TextInserter()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ChatCleanup.timingSink = { [log] report in log.info(report) }
        // The pill's × is the cancel key, clicked.
        pill.onConfirm = { [weak self] in
            Task { @MainActor in await self?.controller.runPendingCommand() }
        }
        pill.onCancel = { [weak self] in
            Task { @MainActor in await self?.controller.cancelRequested() }
        }
        // Without this, an accessory app's own windows have no ⌘A, ⌘C or ⌘V:
        // AppKit resolves those through the main menu, which an LSUIElement app
        // does not get by default.
        EditMenu.install(viewTarget: self,
                         screenAction: #selector(showScreen(_:)),
                         findAction: #selector(findInHistory))
        log.info("Rawi starting")

        let launchStarted = ContinuousClock.now
        Task { @MainActor in
            self.launchMarks.append("task \(launchStarted.duration(to: .now).milliseconds)ms")
            let (loaded, created) = await FirstRunSetup.loadOrCreate()
            self.launchMarks.append("config \(launchStarted.duration(to: .now).milliseconds)ms")
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
            self.watchSystemAppearance()
            self.startRemoteTriggers()
            // Log and finish wiring BEFORE asking for the microphone. The request
            // does not return until the user answers the system dialog, so
            // awaiting it here left the menu bar unrefreshed and the permission
            // state unlogged for as long as the prompt sat on screen.
            self.learnTerms()
            self.logPermissions()
            self.refreshChecklist()
            self.checklistTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                MainActor.assumeIsolated { self.refreshChecklist() }
            }
            self.menuBar.refresh(state: .idle, permissions: Permissions.current())
            self.menuBar.setRecent(self.recentFromHistory())
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A first run, or a Mac where dictation cannot work yet, opens setup
                // instead — which asks for the microphone at its own step, with the
                // reason on screen, rather than as a bare system prompt at launch.
                let readiness = await SetupStatus.current(config: self.config)
                if !self.config.setupCompleted || !readiness.canDictate {
                    self.log.info("Opening setup (completed: \(self.config.setupCompleted), "
                                  + "can dictate: \(readiness.canDictate))")
                    self.showSetup()
                    return
                }
                let granted = await Permissions.requestMicrophone()
                self.log.info("Microphone \(granted ? "granted" : "not granted")")
                self.menuBar.refresh(state: self.controller.state,
                                     permissions: Permissions.current())
            }
        }
    }

    /// What setup still has outstanding, for the rail and the menu panel.
    ///
    /// Checked on a timer as well as at the obvious moments: permissions are granted
    /// in another app, and a model finishes downloading in its own time, so nothing
    /// here can wait to be told.
    private func refreshChecklist() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await SetupStatus.current(config: self.config)
            let checklist = SetupChecklist.make(status: status, config: self.config)
            self.mainWindow.setup.checklist = checklist
            self.menuBar.setOutstanding(checklist.isComplete ? nil : checklist)
            if checklist.isComplete != self.checklistWasComplete {
                self.checklistWasComplete = checklist.isComplete
                if !checklist.isComplete {
                    self.log.warn("Setup outstanding: "
                                  + checklist.outstanding.map { "\($0.title) — \($0.detail)" }
                                      .joined(separator: " | "))
                }
            }
        }
    }

    /// First-run setup, also reachable later from the menu bar.
    private func showSetup(at step: SetupStep? = nil) {
        let window = setupWindow ?? SetupWindow()
        setupWindow = window
        if let step { window.model.step = step }
        window.model.settings.onCapture = mainWindow.settings.onCapture
        window.model.launchedWithInputMonitoring = Permissions.current().inputMonitoring
            && monitor is HotkeyMonitor
        window.model.onFinish = { [weak self] in
            self?.setupWindow?.close()
            self?.log.info("Setup finished")
            self?.refreshChecklist()
        }
        window.model.onRestart = { [weak self] in self?.relaunch() }
        window.show(appearance: config.appearance.resolved(systemIsDark: Appearance.systemIsDark))
    }

    /// Starts a fresh copy of Rawi and quits this one — the only way a newly granted
    /// Input Monitoring reaches the key listener.
    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func showScreen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let screen = Screen(rawValue: raw) else { return }
        mainWindow.show(screen)
    }

    @objc private func findInHistory() {
        mainWindow.show(.history)
        mainWindow.focusSearch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        (controller?.engine as? WhisperServerEngine)?.stop()
        transformMonitor?.stop()
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

    /// Applies the configured appearance. `system` deliberately assigns nil, which
    /// is AppKit's "inherit" — pinning a concrete appearance there would stop the
    /// app following the OS.
    private func applyAppearance() {
        NSApp.appearance = config.appearance.nsAppearanceName.map { NSAppearance(named: $0) } ?? nil
        let resolved = config.appearance.resolved(systemIsDark: Appearance.systemIsDark)
        menuBar?.setAppearance(resolved)
        mainWindow?.setAppearance(resolved)
    }

    /// Follow a live OS light/dark switch without a restart, when set to `system`.
    private func watchSystemAppearance() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.config.appearance == .system else { return }
                self.applyAppearance()
            }
        }
    }

    // MARK: - Graph

    private func buildGraph() {
        let env = DotEnv.load(from: Config.envFile)
        // Sealed by default. If the keychain will not hand over a key, history still
        // works, unsealed, and the log says so rather than losing every dictation.
        var cipher: (any HistoryCipher)?
        let keyStarted = ContinuousClock.now
        if config.history.encrypted {
            do { cipher = try FileKeyHistoryCipher(migrate: LegacyKeychainHistoryKey.takeIfPresent) }
            catch { log.error("History encryption unavailable (\(error)); writing it unsealed") }
        }
        launchMarks.append("key \(keyStarted.duration(to: .now).milliseconds)ms")
        let historyStarted = ContinuousClock.now
        history = HistoryStore(limit: config.history.limit,
                               retentionDays: config.history.retentionDays, cipher: cipher)
        launchMarks.append("history \(historyStarted.duration(to: .now).milliseconds)ms")
        log.info("Launch: \(launchMarks.joined(separator: ", "))")
        log.info("History: \(history.count) entries, \(cipher == nil ? "plain" : "encrypted"), "
                 + (config.history.retentionDays == 0 ? "kept until the limit"
                    : "kept \(config.history.retentionDays) days"))
        // Off the launch path: nothing waits on it, and a directory with hundreds
        // of stale files takes long enough to read that it would show.
        let historyForSweep = history
        let sweepLog = log
        Task.detached(priority: .background) {
            guard let historyForSweep else { return }
            let removed = historyForSweep.sweepOrphanedAudio(in: Config.recordingsDirectory)
            if removed > 0 { sweepLog.info("Deleted \(removed) recordings nothing pointed at") }
        }
        vocabulary = VocabularyStore()
        let profileCipher = cipher
        destinations = DestinationStore()
        transforms = TransformStore()
        commands = CommandStore()
        mainWindow = MainWindow(
            store: history, vocabularyStore: vocabulary, destinationStore: destinations,
            transformStore: transforms, commandStore: commands,
            appearance: config.appearance.resolved(systemIsDark: Appearance.systemIsDark))
        let engine = makeEngine(env: env)
        warmEngine(engine)
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
        // The same probe the focus trigger reports on, so the log and the paste
        // decision can never disagree.
        controller.focusProbe = focusProbe
        // The dictionary fills itself the way Wispr Flow's does: from what you fix.
        let watcher = SystemEditWatcher()
        watcher.onCorrection = { [weak self] correction, app in
            guard let self else { return }
            let isNew = self.vocabulary.learnCorrection(heard: correction.heard,
                                                        fixed: correction.fixed, app: app,
                                                        alias: correction.aliasable)
            if isNew {
                self.log.info("Learned “\(correction.fixed)” — you corrected “\(correction.heard)” in \(app ?? "an app")")
                self.mainWindow.reload()
            }
        }
        watcher.onNote = { [weak self] note in self?.log.info("Edit watch: \(note)") }
        controller.editWatcher = watcher
        controller.mayWatchEdits = { [weak self] bundleID in
            guard let self else { return false }
            return self.config.history.enabled && !self.config.history.excludes(bundleID)
        }
        controller.vocabulary = { [weak self] in self?.vocabulary.snapshot() ?? .empty }
        controller.destination = { [weak self] bundleID in
            guard let self else { return nil }
            // Only ask a browser for its URL. Anything else pays nothing.
            let url = BrowserContext.activeURL(bundleID: bundleID)
            // Read at key-press, while the cursor is still in the field you mean.
            let field = FieldContext.focused()
            let rule = DestinationMatcher.match(bundleID: bundleID, url: url, field: field,
                                                rules: self.destinations.rules)
            // Log the signals, not just the outcome: "no rule matched" is
            // indistinguishable from "the URL could not be read" otherwise, and
            // those need completely different fixes.
            let host = url.flatMap { URL(string: $0)?.host } ?? "—"
            self.log.info("""
                Destination: \(rule?.name ?? "none") \
                [app \(bundleID ?? "unknown"), page \(host), field \(field?.name ?? "—")\
                \(url == nil && BrowserContext.scriptable[bundleID ?? ""] != nil
                   ? ", url unreadable: \(BrowserContext.lastError ?? "no window")" : "")]
                """)
            return rule
        }
        mainWindow.onRetry = { [weak self] entry in
            guard let self, let path = entry.audioPath else { return }
            Task { @MainActor in
                self.log.info("Retrying a dictation that failed")
                await self.controller.retry(audioPath: path, appName: entry.appName,
                                            bundleID: entry.bundleID)
            }
        }
        wireTransforms(env: env)
        wirePolish(env: env)
        wireInsightsWriter(env: env)
        controller.onRecord = { [weak self] entry in
            guard let self else { return }
            guard self.config.history.enabled else { return }
            // Exclusions are checked here rather than in the controller: what is
            // private is a policy question, not a dictation one.
            guard !self.config.history.excludes(entry.bundleID) else {
                self.log.info("Not recorded — \(entry.appName ?? "that app") is excluded")
                return
            }
            self.history.append(entry)
            self.learnTerms()
            self.mainWindow.reload()
            self.menuBar.setRecent(self.recentFromHistory())
        }
        mainWindow.insights.terms = { [weak self] in self?.vocabulary.terms.map(\.term) ?? [] }
        mainWindow.insights.taught = { [weak self] in
            self?.vocabulary.terms.filter(\.learnedFromCorrection).reversed().map(\.term) ?? []
        }
        mainWindow.insights.profileStore = VoiceProfileStore(cipher: profileCipher)
        let performer = SystemCommandPerformer(env: env)
        controller.commandRunner = CommandRunner(store: commands, performer: performer)
        mainWindow.commands.perform = { action, text in try await performer.perform(action, text: text) }
        mainWindow.commands.key = HotkeyConfig.symbolic(config.commandHotkey)
        menuBar = MenuBarController(controller: controller, log: log)
        publishHotkeyLabels()
        menuBar.onOpenWindow = { [weak self] in self?.mainWindow.show() }
        menuBar.onUndo = { [weak self] in _ = self?.controller.undoTransform() }
        menuBar.onOpenSettings = { [weak self] in self?.mainWindow.show(.settings) }
        menuBar.onOpenSetup = { [weak self] in self?.showSetup() }
        mainWindow.onOpenSetup = { [weak self] step in self?.showSetup(at: step) }
        // Let go of the global hotkeys while one is being recorded, or the key you
        // are trying to assign is swallowed by the key it is already assigned to.
        mainWindow.settings.onCapture = { [weak self] capturing in
            guard let self else { return }
            if capturing {
                self.monitor?.stop()
                self.transformMonitor?.stop()
                self.log.info("Hotkeys released while a shortcut is recorded")
            } else {
                self.startMonitoring()
            }
        }
        menuBar.onAction = { [weak self] id in
            guard let self else { return }
            switch id {
            case "dictate", "transform":
                let intent: RecordingIntent = id == "transform" ? .transform : .dictate
                Task { @MainActor in
                    // Clicked twice, it stops — from a menu there is no key to release.
                    if self.controller.state.recordingMode != nil {
                        await self.controller.handle(.endedHold)
                    } else {
                        await self.controller.handle(.beganHold, intent: intent)
                    }
                }
            default: break
            }
        }
        applyAppearance()
        tapPattern = TapPattern(doubleTapWindow: .milliseconds(config.doubleTapWindowMs),
                                minHold: .milliseconds(config.minHoldMs))
    }

    /// One source of truth for every printed shortcut, refreshed whenever the
    /// config or the permission state changes.
    private func publishHotkeyLabels() {
        let granted = Permissions.current().inputMonitoring
        let labels = HotkeyLabels(config: config, inputMonitoringGranted: granted)
        menuBar.setLabels(labels)
        pill.setLabels(labels)
        mainWindow.setLabels(labels)
        mainWindow.settings.inputMonitoringGranted = granted

        // Checked at launch, not only when someone edits a key: the shipped
        // defaults once put dictate and transform on the same chord, and nothing
        // in the app said so.
        let bound = config.effectiveDictateHotkey(inputMonitoringGranted: granted)
        let assignments = [("Dictate", bound), ("Transform clipboard", config.transformHotkey),
                           ("Speak a command", config.commandHotkey), ("Cancel", config.cancelHotkey)]
        let clashing = HotkeyConfig.clashes(in: assignments)
        if !clashing.isEmpty {
            log.warn("""
                \(clashing.joined(separator: " and ")) are on the same combination, \
                so only one of them works. Change one in Settings.
                """)
        }
    }

    /// Keeps the dictionary in step with what you actually say.
    ///
    /// Runs after every dictation rather than on a schedule: it is a pass over at
    /// most 500 short strings, and a term learned an hour from now is a term that
    /// spelled your colleague's name wrong an hour longer.
    private func learnTerms() {
        let learned = TermLearner.learn(from: history.all(),
                                        known: vocabulary.terms,
                                        blocked: vocabulary.blocked)
        let change = vocabulary.syncLearned(learned)
        for term in change.added { log.info("Learned “\(term)” from your own dictations") }
        for term in change.dropped { log.info("Dropped “\(term)” — you stopped saying it") }
    }

    /// What the menu's Recent shows. Read from history rather than from an
    /// in-memory list: that list started empty on every launch, so a user with
    /// hundreds of stored dictations still saw "Nothing yet today."
    ///
    /// Transform rows are left out. Recent is for re-copying something you said,
    /// and a transform's row holds the clipboard text it started from.
    private func recentFromHistory(limit: Int = 6) -> [RecentDictation] {
        history.all()
            .lazy
            .filter { $0.kind == .dictation }
            .prefix(limit)
            .map { RecentDictation(text: $0.cleaned, script: $0.script, at: $0.at) }
    }

    /// The model that writes the voice profile on Insights: the transform model,
    /// since the job is writing, not cleaning. Nil when there is no model to ask.
    private func wireInsightsWriter(env: DotEnv) {
        let kind = config.cleanup.provider
        let model = config.cleanup.transformModel.isEmpty ? config.cleanup.models.arabic
                                                          : config.cleanup.transformModel
        let key: String? = switch kind {
        case .openai: env["OPENAI_API_KEY"]
        case .anthropic: env["ANTHROPIC_API_KEY"]
        case .ollama, .off: nil
        }
        guard kind != .off, kind == .ollama || !(key ?? "").isEmpty, !model.isEmpty else {
            mainWindow.insights.writer = nil
            return
        }
        mainWindow.insights.writer = { system, request in
            try await ChatCleanup(kind: kind, apiKey: key, model: model, prompt: system,
                                  wrap: { $0 }).clean(request, instruction: "")
        }
    }

    /// The polisher, when the mode asks for one. Built here with the rest of the
    /// provider graph, and rebuilt on a config reload so changing the mode or the
    /// model in config.json takes effect without a relaunch.
    private func wirePolish(env: DotEnv) {
        do {
            controller.polisher = try CleanupProviderFactory.makePolisher(
                config: config, env: env)
            if controller.polisher == nil {
                log.info("Cleanup mode: clean — filler and punctuation only")
            } else if !config.cleanup.polishModel.isEmpty {
                log.info("Cleanup mode: polish via \(config.cleanup.polishModel)")
            } else {
                log.info("""
                    Cleanup mode: polish — English via \(config.cleanup.models.latin), \
                    anything with Arabic via \(config.cleanup.models.arabic)
                    """)
            }
        } catch {
            log.error("Polish disabled: \(error.localizedDescription)")
            controller.polisher = nil
        }
    }

    /// Transforms need a model. With cleanup off there is nothing to ask, and the
    /// transform key says so on the pill rather than doing nothing.
    private func wireTransforms(env: DotEnv) {
        let rewriter: (any CleanupProvider)?
        do {
            rewriter = try CleanupProviderFactory.makeTransformer(config: config, env: env)
        } catch {
            log.error("Transforms disabled: \(error.localizedDescription)")
            rewriter = nil
        }
        guard let rewriter else {
            controller.transformRunner = nil
            log.info("Transforms disabled — cleanup.provider is off")
            return
        }
        controller.transformRunner = TransformRunner(store: transforms, rewriter: rewriter)
        // The try-it box on the Transforms screen runs the same model the hotkey
        // does, so tuning an instruction there means something.
        mainWindow.transforms.preview = { text, instruction in
            try await rewriter.clean(wrapTransform(text: text, instruction: instruction))
        }
        controller.onTransform = { [weak self] outcome in
            self?.mainWindow.reload()
            _ = outcome
        }
        let transformModel = config.cleanup.transformModel.isEmpty
            ? config.cleanup.models.arabic
            : config.cleanup.transformModel
        log.info("Transforms via \(config.cleanup.provider.rawValue) \(transformModel)")
    }

    /// A misconfigured provider must not prevent the app from launching — it degrades
    /// to something that works and says so in the log and the menu bar.
    private func makeEngine(env: DotEnv) -> any TranscriptionEngine {
        do {
            return try TranscriptionEngineFactory.make(config: config, env: env, log: log)
        } catch {
            log.error("Falling back to local whisper: \(error.localizedDescription)")
            var fallback = config
            fallback.engine = .whispercpp
            return try! TranscriptionEngineFactory.make(config: fallback, env: env, log: log)
        }
    }

    /// Loads the model before anybody needs it. Costs nothing but memory, and it is
    /// the difference between the first dictation of the day taking a second and
    /// taking four.
    private func warmEngine(_ engine: any TranscriptionEngine) {
        if let resident = engine as? WhisperServerEngine { residentEngine = resident }
        // Deliberately not `engine`: once the command line is standing in, the
        // controller's engine is no longer the resident one, and reading it there
        // is how a stand-in became permanent.
        guard let resident = residentEngine else { return }
        Task.detached(priority: .utility) {
            let ready = await resident.warmAll()
            await MainActor.run { self.useResidentModel(resident, ifReady: ready) }
        }
    }

    /// Switches between the resident model and the command line, both ways.
    ///
    /// The command line loads the model from disk on every dictation, which is
    /// several seconds each time — a fine stand-in for one dictation and a bad way
    /// to spend a day. It used to be the latter: a single slow health check at
    /// launch, on a machine busy with something else, swapped the engine out and
    /// nothing ever swapped it back. Caught in a real log, six seconds a dictation
    /// for an hour, on a model that answers in fifty milliseconds.
    @MainActor
    private func useResidentModel(_ resident: WhisperServerEngine, ifReady ready: Bool) {
        let onResident = controller.engine is WhisperServerEngine
        guard ready != onResident else { return }          // already where it should be
        let env = DotEnv.load(from: Config.envFile)
        if ready {
            log.info("whisper-server answered; back on the resident model")
            controller.reconfigure(config: config, engine: resident,
                                   cleanup: makeCleanup(env: env))
            return
        }
        var fallback = config
        fallback.whispercpp.useServer = false
        guard let cli = try? TranscriptionEngineFactory.make(
            config: fallback, env: env, log: log) else { return }
        log.info("whisper-server did not answer; the command line stands in until it does")
        controller.reconfigure(config: config, engine: cli, cleanup: makeCleanup(env: env))
    }

    /// Kept whether or not it is the engine in use, so a stand-in can be handed back.
    private var residentEngine: WhisperServerEngine?

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
                case .transform: await self.controller.handle(.beganHold, intent: .transform)
                case .handsFree: await self.controller.handle(.beganDoubleTap)
                case .stop: await self.controller.handle(.endedHold)
                case .cancel: await self.controller.cancelRequested()
                case .window: self.mainWindow.show()
                case .menu: self.menuBar.togglePanel()
                case .undo: _ = self.controller.undoTransform()
                case .editSelfTest:
                    // Paste a known sentence into the focused field, correct it
                    // through Accessibility after a moment, and let the real watcher
                    // find the correction. Used with a scratch document in front.
                    try? await Task.sleep(for: .seconds(2))
                    let sentence = "We manage every laptop with Kanjee now."
                    guard self.inserter.insert(sentence, restoringClipboard: true) else {
                        self.log.warn("Edit self-test: could not paste"); return
                    }
                    self.controller.editWatcher?.watch(inserted: sentence, appName: "Self-test")
                    try? await Task.sleep(for: .seconds(2))
                    let edited = SystemEditWatcher.simulateCorrection(from: "Kanjee", to: "Kandji")
                    self.log.info("Edit self-test: correction \(edited)")
                case .commandSelfTest:
                    // Runs a command the way the key would, without speaking: proves the
                    // action itself works, including the permission it needs.
                    // Sent again while a question is up, it answers it.
                    if await self.controller.runPendingCommand() { return }
                    // Through a file: the trigger is a separate process, so its
                    // environment never reaches this one.
                    let spokenFile = Config.supportDirectory.appendingPathComponent("command-test.txt")
                    let phrase = (try? String(contentsOf: spokenFile, encoding: .utf8))?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "remind me to check that Rawi can add reminders"
                    await self.controller.runSpokenCommand(phrase)
                case .focus:
                    // Asked after a pause, so whoever sent it can put an app in front.
                    try? await Task.sleep(for: .seconds(2))
                    let verdict = self.focusProbe.probe()
                    let field = FieldContext.focused()
                    self.log.info("Focus probe: \(self.focusProbe.lastSeen) [\(verdict.rawValue)] field labels: \(field?.labels ?? [])")
                case .benchmark:
                    let path = ProcessInfo.processInfo.environment["RAWI_BENCH_WAV"]
                        ?? Config.recordingsDirectory
                            .appendingPathComponent("benchmark.wav").path
                    await self.controller.retry(audioPath: path, appName: "Benchmark",
                                                bundleID: "benchmark", records: false)
                }
            }
        }
    }

    // MARK: - Input

    private func startMonitoring() {
        monitor?.stop()
        activeDictateKey = nil
        carbonCarriesTransform = false
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
        // Outside the catch on purpose: dictation failing to bind is no reason for
        // transforms to lose their key too.
        startTransformHotkey(dictateKey: activeDictateKey)
        startCommandHotkey(dictateKey: activeDictateKey)
    }

    private func startEventTap() throws {
        guard let matcher = HotkeyConfig.parse(config.hotkey) else {
            throw HotkeyError.carbonNeedsCombination(config.hotkey)
        }
        let monitor = HotkeyMonitor(
            matcher: matcher,
            onPress: { MainActor.assumeIsolated { self.feed(self.tapPattern.press(at: .now)) } },
            onRelease: { MainActor.assumeIsolated { self.feed(self.tapPattern.release(at: .now)) } },
            onEscape: { MainActor.assumeIsolated { self.escapePressed() } },
            onChord: { MainActor.assumeIsolated { self.shortcutNotHold() } })
        try monitor.start()
        self.monitor = monitor
        log.info("Listening for \(config.hotkey) (listen-only tap)")
        activeDictateKey = HotkeyConfig.parse(config.hotkey)
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

        // The transform key rides on this same monitor when dictation is on Carbon
        // too — one registration, one handler. It only needs its own monitor when
        // dictation is using the event tap instead.
        var transformCode: UInt16?
        var transformMods = CGEventFlags()
        if case .keyCode(let tc, let tm)? = HotkeyConfig.parse(config.transformHotkey),
           !(tc == code && tm == mods) {
            transformCode = tc
            transformMods = tm
        }

        let monitor = CarbonHotkeyMonitor(
            keyCode: code, modifiers: mods,
            cancelKeyCode: cancelCode, cancelModifiers: cancelMods,
            transformKeyCode: transformCode, transformModifiers: transformMods,
            onPress: { MainActor.assumeIsolated { self.feed(self.tapPattern.press(at: .now)) } },
            onRelease: { MainActor.assumeIsolated { self.feed(self.tapPattern.release(at: .now)) } },
            onCancel: { MainActor.assumeIsolated { self.escapePressed() } },
            onTransformPress: {
                MainActor.assumeIsolated {
                    self.feed(self.transformTapPattern.press(at: .now), intent: .transform)
                }
            },
            onTransformRelease: {
                MainActor.assumeIsolated {
                    self.feed(self.transformTapPattern.release(at: .now), intent: .transform)
                }
            })
        try monitor.start()
        self.monitor = monitor
        carbonCarriesTransform = transformCode != nil && monitor.transformRegistered
        log.info("""
            Listening for \(hotkey); cancel with \(config.cancelHotkey)\
            \(carbonCarriesTransform ? "; transform on \(config.transformHotkey)" : "")
            """)
        activeDictateKey = .keyCode(code, modifiers: mods)
    }

    /// Registers the transform key on its own Carbon monitor. Skipped when it would
    /// claim the same combination dictation is already using: two registrations of
    /// one chord means the second silently loses, and a dead key is worse than an
    /// absent one.
    private func startTransformHotkey(dictateKey: HotkeyMatcher?) {
        transformMonitor?.stop()
        transformMonitor = nil
        // Already bound alongside dictation on the one Carbon monitor.
        guard !carbonCarriesTransform else { return }
        guard case .keyCode(let code, let mods)? = HotkeyConfig.parse(config.transformHotkey) else {
            log.warn("""
                transformHotkey “\(config.transformHotkey)” is not a modifier+key                 combination; transforms have no key.
                """)
            return
        }
        if case .keyCode(let dc, let dm)? = dictateKey, dc == code, dm == mods {
            log.warn("""
                transformHotkey “\(config.transformHotkey)” is the dictation hotkey;                 transforms have no key until one of them changes.
                """)
            return
        }
        let monitor = CarbonHotkeyMonitor(
            keyCode: nil, modifiers: [],
            transformKeyCode: code, transformModifiers: mods,
            onTransformPress: {
                MainActor.assumeIsolated {
                    self.feed(self.transformTapPattern.press(at: .now), intent: .transform)
                }
            },
            onTransformRelease: {
                MainActor.assumeIsolated {
                    self.feed(self.transformTapPattern.release(at: .now), intent: .transform)
                }
            })
        do {
            try monitor.start()
        } catch {
            log.warn("Transform hotkey failed to register: \(error.localizedDescription)")
            return
        }
        guard monitor.transformRegistered else {
            log.warn("""
                Another app already owns \(config.transformHotkey);                 change transformHotkey in \(Config.configFile.path).
                """)
            return
        }
        transformMonitor = monitor
        log.info("Transform on \(config.transformHotkey) (no permissions required)")
    }

    /// The command key, on its own Carbon registration like the transform key.
    private func startCommandHotkey(dictateKey: HotkeyMatcher?) {
        commandMonitor?.stop()
        commandMonitor = nil
        guard case .keyCode(let code, let mods)? = HotkeyConfig.parse(config.commandHotkey) else {
            log.warn("commandHotkey “\(config.commandHotkey)” is not a modifier+key combination; "
                     + "commands have no key.")
            return
        }
        if case .keyCode(let dc, let dm)? = dictateKey, dc == code, dm == mods {
            log.warn("commandHotkey “\(config.commandHotkey)” is the dictation hotkey; "
                     + "commands have no key until one of them changes.")
            return
        }
        let monitor = CarbonHotkeyMonitor(
            keyCode: nil, modifiers: [],
            transformKeyCode: code, transformModifiers: mods,
            onTransformPress: {
                MainActor.assumeIsolated {
                    // The same key answers a confirmation that is already on screen.
                    let press: @MainActor () -> Void = {
                        self.feed(self.commandTapPattern.press(at: .now), intent: .command)
                    }
                    Task { @MainActor [controller = self.controller] in
                        let answered = await controller?.confirmCommand() ?? false
                        if !answered { press() }
                    }
                }
            },
            onTransformRelease: {
                MainActor.assumeIsolated {
                    guard self.controller.commandRunner?.pending == nil else { return }
                    self.feed(self.commandTapPattern.release(at: .now), intent: .command)
                }
            })
        do { try monitor.start() } catch {
            log.warn("Command hotkey failed to register: \(error.localizedDescription)")
            return
        }
        guard monitor.transformRegistered else {
            log.warn("Another app already owns \(config.commandHotkey); change commandHotkey in "
                     + "\(Config.configFile.path).")
            return
        }
        commandMonitor = monitor
        log.info("Commands on \(config.commandHotkey) (no permissions required)")
    }

    private func feed(_ outcome: TapOutcome, intent: RecordingIntent = .dictate) {
        // You are about to speak, so the model had better be loaded by the time you
        // stop. Nothing waits on this.
        if outcome == .beganHold || outcome == .beganDoubleTap {
            warmEngine(controller.engine)
            // While you speak, the polisher reads its instructions, so the pause after
            // you stop is only the typing of your words.
            if intent == .dictate, let polisher = controller.polisher {
                Task.detached(priority: .utility) { await polisher.warm() }
            }
        }
        if outcome == .pendingShortTap { schedulePendingTapTimer() }
        if outcome == .beganDoubleTap || outcome == .beganHold { pendingTapTimer?.invalidate() }
        guard outcome != .ignored else { return }
        Task { @MainActor in await controller.handle(outcome, intent: intent) }
    }

    /// The bare dictation modifier was the start of a shortcut — ⌥← held a moment
    /// too long. The recording it started is dropped without a word: nothing was
    /// said, and nothing went wrong.
    private func shortcutNotHold() {
        tapPattern.reset()
        pendingTapTimer?.invalidate()
        log.info("Hotkey was part of a shortcut; recording dropped")
        Task { @MainActor in await controller.handle(.discardShortTap) }
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
        stateEnteredAt = Date()
        menuBar.refresh(state: state, permissions: Permissions.current())
        menuBar.setRecent(recentFromHistory())

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
            // Keep the frame timer alive while the mark unflattens: cutting it at
            // idle would snap the line back to a waveform instead of returning it.
            if markMotion.isSettled {
                pillTimer?.invalidate()
                pillTimer = nil
                pill.hide()
            }
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
        lastFrameAt = Date()
        updatePill()
        pillTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated { self.updatePill() }
        }
    }

    private func updatePill() {
        let state = controller.state
        let now = Date()
        let dt = max(0, now.timeIntervalSince(lastFrameAt))
        lastFrameAt = now
        markMotion.advance(to: state, dt: dt,
                           elapsed: now.timeIntervalSince(stateEnteredAt))
        if state.recordingMode != nil { meter.advance(raw: recorder.level, dt: dt) } else { meter.reset() }
        let elapsed: Duration = recordingStart.map { $0.duration(to: .now) } ?? .zero
        var remaining: Duration?
        if state.recordingMode == .handsFree {
            let limit = Duration.seconds(config.maxSessionSeconds)
            remaining = limit - elapsed
        }
        // The ⌘V hint only appears where it is true: with Accessibility granted
        // the text is already in the document.
        menuBar?.updateLive(level: meter.level, peak: meter.peak, elapsed: elapsed,
                            detectedLanguage: controller.lastDetectedLanguage,
                            motion: markMotion)
        // Once the mark has finished returning to a waveform there is nothing left
        // to draw, so the frame timer stops and the pill goes away.
        if state == .idle, markMotion.isSettled {
            pillTimer?.invalidate()
            pillTimer = nil
            pill.hide()
            return
        }
        pill.show(state: state, level: meter.level, peak: meter.peak, elapsed: elapsed,
                  remaining: remaining, pasteHint: controller.awaitingManualPaste,
                  motion: markMotion)
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
            || reloaded.transformHotkey != config.transformHotkey
            || reloaded.commandHotkey != config.commandHotkey
        let transformsChanged = reloaded.cleanup != config.cleanup
        config = reloaded
        let env = DotEnv.load(from: Config.envFile)
        // The resident server holds whatever model it was started with, so a model
        // change in Settings has to take it down. Leaving it up was why switching
        // to a faster model changed nothing at all.
        (controller.engine as? WhisperServerEngine)?.stop()
        let engine = makeEngine(env: env)
        controller.reconfigure(config: config, engine: engine,
                               cleanup: makeCleanup(env: env))
        warmEngine(engine)
        tapPattern = TapPattern(doubleTapWindow: .milliseconds(config.doubleTapWindowMs),
                                minHold: .milliseconds(config.minHoldMs))
        if hotkeyChanged { startMonitoring() }
        publishHotkeyLabels()
        if transformsChanged { wireTransforms(env: env)
        wirePolish(env: env)
        wireInsightsWriter(env: env) }
        history.setRetention(days: config.history.retentionDays)
        refreshChecklist()
        applyAppearance()
        log.info("Config reloaded (engine=\(config.engine.rawValue), "
                 + "cleanup=\(config.cleanup.provider.rawValue), hotkey=\(config.hotkey))")
    }
}
