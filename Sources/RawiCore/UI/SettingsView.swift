import AppKit
import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var config: Config
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    @Published public var installedOllama: [String] = []
    @Published public var ollamaReachable = false
    @Published public var recording: String?
    @Published public var saveError: String?

    /// Called with true while a shortcut is being recorded.
    ///
    /// The global hotkeys have to be released for the duration. A Carbon hotkey is
    /// consumed application-wide — including inside this app — so with dictation
    /// bound to ⌥Space, pressing ⌥Space here started a dictation and the recorder
    /// never saw the key at all. It looked exactly like the keyboard was dead.
    public var onCapture: ((Bool) -> Void)?

    private var captureTimeout: Task<Void, Never>?

    /// What happened when a pressed combination was offered to a key.
    public enum Assignment: Equatable {
        case saved
        /// Another Rawi key already owns it. Nothing was written.
        case clashes(with: Key)
        /// Not bindable at all: a bare key with no modifier would take that key
        /// away from every app on the Mac.
        case unusable
    }

    /// A combination that was pressed but refused, waiting on a swap or a dismiss.
    @Published public var pendingClash: (pressed: String, wanted: Key, owner: Key)?

    /// Where this screen reads and writes. Injectable, and injected by every test:
    /// a view model that defaults to the real config file will eventually be
    /// constructed by a test, and then the test edits the user's live settings. It
    /// has happened once — a hotkey test changed the running app's shortcut.
    private let url: URL

    /// Which keys exist, in the order the screen lists them. The label is what a
    /// clash is reported against, so it is the user's word for the key.
    public enum Key: String, CaseIterable {
        case dictate, transform, command, cancel

        public var label: String {
            switch self {
            case .dictate: "Dictate"
            case .transform: "Transform clipboard"
            case .command: "Speak a command"
            case .cancel: "Cancel"
            }
        }

        public var detail: String {
            switch self {
            case .dictate: "Hold to speak. Double-tap for hands-free."
            case .transform: "Hold, say what to do with the clipboard."
            case .command: "Hold, say a command. Nothing is typed."
            case .cancel: "Drops a recording, or stops work already running."
            }
        }
    }

    /// Whether Input Monitoring is granted, which decides which of the two
    /// dictation keys is really listening.
    public var inputMonitoringGranted: Bool = Permissions.current().inputMonitoring

    public init(config: Config = .default, url: URL = Config.configFile,
                inputMonitoringGranted: Bool = Permissions.current().inputMonitoring) {
        self.config = config
        self.url = url
        self.inputMonitoringGranted = inputMonitoringGranted
    }

    /// True when a capture gave up on its own rather than being used.
    @Published public var captureExpired = false
    /// Why the last key you pressed was not saved. Refusing a key without saying
    /// so looked exactly like the setting being broken.
    @Published public var captureProblem: String?

    public func beginCapture(_ key: Key) {
        guard recording != key.rawValue else { return }
        pendingClash = nil
        captureExpired = false
        captureProblem = nil
        recording = key.rawValue
        onCapture?(true)
        // A backstop, not a deadline. Eight seconds was long enough to click the
        // field, look down at the keyboard, and have the capture quietly end
        // before the keypress — which then reached the hotkey it was trying to
        // replace and started a dictation.
        captureTimeout?.cancel()
        captureTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.captureExpired = true
            self?.endCapture()
        }
    }

    public func endCapture() {
        captureTimeout?.cancel()
        captureTimeout = nil
        guard recording != nil else { return }
        recording = nil
        onCapture?(false)
    }

    public func value(for key: Key) -> String {
        switch key {
        // The bound key, not the requested one: on a Mac without Input Monitoring
        // the Carbon backend substitutes the fallback, and a settings screen that
        // shows the other value is showing a shortcut that does nothing.
        case .dictate: config.effectiveDictateHotkey(
            inputMonitoringGranted: inputMonitoringGranted)
        case .transform: config.transformHotkey
        case .command: config.commandHotkey
        case .cancel: config.cancelHotkey
        }
    }

    /// Offers a pressed combination to a key.
    ///
    /// A clash is refused rather than saved. The screen used to write it and then
    /// report the collision in red, which left a config where dictation and
    /// transform were the same chord and one of them silently lost — including,
    /// briefly, a transform key that could not be changed because every press
    /// collided with itself.
    @discardableResult
    public func assign(_ raw: String, to key: Key) -> Assignment {
        captureProblem = nil
        switch HotkeyConfig.parse(raw) {
        case .keyCode?:
            break
        case .modifierFlag?:
            // One modifier on its own is a dictation key, and only where the event
            // tap can see it. Transform and cancel go through a registration that
            // can only bind a combination.
            guard key == .dictate else {
                captureProblem = "\(key.label) needs a combination, like \(HotkeyConfig.symbolic(value(for: key)))."
                return .unusable
            }
            guard inputMonitoringGranted else {
                captureProblem = "\(HotkeyConfig.symbolic(raw)) on its own needs Input Monitoring. "
                    + "Until then, use a combination."
                return .unusable
            }
        case nil:
            captureProblem = "Rawi can’t use that key. Try a letter, a number, Space or an F-key, with a modifier like ⌥."
            return .unusable
        }
        if let owner = Key.allCases.first(where: {
            $0 != key && HotkeyConfig.parse(value(for: $0)) == HotkeyConfig.parse(raw)
        }) {
            pendingClash = (raw, key, owner)
            return .clashes(with: owner)
        }
        pendingClash = nil
        set(raw, for: key)
        return .saved
    }

    /// Takes the clash as an instruction: each key gets the other's combination.
    public func swapPending() {
        guard let clash = pendingClash else { return }
        let previous = value(for: clash.wanted)
        set(clash.pressed, for: clash.wanted)
        set(previous, for: clash.owner)
        pendingClash = nil
    }

    public func dismissPending() { pendingClash = nil }

    public func set(_ raw: String, for key: Key) {
        switch key {
        case .dictate:
            config.hotkey = raw
            // The Carbon backend cannot bind a bare modifier, so it falls back to
            // this. Keeping the two in step means the key you chose is the key you
            // get on a Mac that cannot grant Input Monitoring.
            if HotkeyConfig.isCarbonCompatible(raw) { config.fallbackHotkey = raw }
        case .transform: config.transformHotkey = raw
        case .command: config.commandHotkey = raw
        case .cancel: config.cancelHotkey = raw
        }
        save()
    }

    /// True when the key you asked for could not be bound and the fallback took
    /// over, which is the normal case on a managed Mac.
    public var dictateIsSubstituted: Bool {
        value(for: .dictate) != config.hotkey
    }

    public var clashing: [String] {
        HotkeyConfig.clashes(in: Key.allCases.map { ($0.label, value(for: $0)) })
    }

    public func clashes(_ key: Key) -> Bool { clashing.contains(key.label) }

    /// Everything is written straight to `config.json`, which the running app is
    /// already watching — so a change here reaches the hotkeys and the providers
    /// through exactly the path a hand edit would take. No second mechanism.
    public func save() {
        do {
            try config.save(to: url)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    public func reload() {
        if let loaded = try? Config.load(from: url) { config = loaded }
        Task { await probeOllama() }
    }

    public func probeOllama() async {
        let models = await OllamaModels.installed()
        installedOllama = OllamaModels.preferred(from: models)
        ollamaReachable = !models.isEmpty
    }

    public var configPath: String { url.path }

    public var whisperModels: [WhisperModel] { ModelStore.installed() }

    public var currentWhisperModel: WhisperModel? {
        ModelStore.model(forPath: config.whispercpp.model)
    }
}

public struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    public init(model: SettingsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Settings", appearance: model.appearance,
                             showInfo: $model.showInfo,
                             info: "Everything here writes to ~/.config/rawi/config.json, "
                                 + "which the running app watches, so changes take effect as you "
                                 + "make them, with no restart. The file stays hand-editable, "
                                 + "and it holds a few things this screen does not show, like "
                                 + "the cleanup prompt itself.")

                if let error = model.saveError {
                    Text("Could not save: \(error)")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                }

                appearanceSection
                keysSection
                transcriptionSection
                cleanupSection
                historySection
                fileSection
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
        .onAppear { model.reload() }
        .onDisappear { model.endCapture() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didResignKeyNotification)) { _ in model.endCapture() }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("Appearance", "The pill stays dark in both. It floats over other "
                            + "people's windows, and a light pill on a light document "
                            + "disappears.") {
            HStack(spacing: 8) {
                ForEach(Appearance.allCases, id: \.self) { option in
                    Button {
                        model.config.appearance = option
                        model.save()
                    } label: {
                        Text(option.displayName)
                            .font(.system(size: TypeScale.body,
                                          weight: model.config.appearance == option
                                              ? .medium : .regular))
                            .foregroundStyle(model.config.appearance == option
                                             ? c(.ink) : c(.muted))
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: Radius.control)
                                .fill(model.config.appearance == option ? c(.bone) : c(.raised)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Keys

    private var keysSection: some View {
        section("Keys", "Click a shortcut and press the combination you want. "
                      + "Carbon hotkeys need no permission but must include a modifier.") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(SettingsViewModel.Key.allCases, id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.label).font(.system(size: TypeScale.body))
                                .foregroundStyle(c(.bone))
                            Text(key.detail).font(.system(size: TypeScale.small))
                                .foregroundStyle(c(.faint))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minWidth: 230, maxWidth: 260, alignment: .leading)

                        HotkeyField(raw: model.value(for: key),
                                    recording: model.recording == key.rawValue,
                                    clashes: model.clashes(key),
                                    appearance: model.appearance,
                                    onStart: { model.beginCapture(key) },
                                    onCapture: { raw in
                                        model.endCapture()
                                        if let raw { model.assign(raw, to: key) }
                                    })
                        Spacer()
                    }
                }
                if let problem = model.captureProblem {
                    Text(problem)
                        .font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.clay))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let clash = model.pendingClash {
                    // The collision is an offer, not a telling-off: you pressed a
                    // key that means something else, and swapping is almost always
                    // what you wanted.
                    HStack(spacing: 10) {
                        Text("\(HotkeyConfig.symbolic(clash.pressed)) is \(clash.owner.label).")
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(c(.bone))
                        Button { model.swapPending() } label: {
                            Text("Swap them")
                                .font(.system(size: TypeScale.small, weight: .medium))
                                .foregroundStyle(c(.ink))
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: Radius.control)
                                    .fill(c(.saffron)))
                        }.buttonStyle(.plain)
                        Button { model.dismissPending() } label: {
                            Text("Keep as it was")
                                .font(.system(size: TypeScale.small))
                                .foregroundStyle(c(.muted))
                        }.buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.control)
                        .fill(c(.saffron).opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control)
                            .strokeBorder(c(.saffron).opacity(0.45))))
                }

                if model.captureExpired {
                    Text("Nothing was pressed, so the shortcut is unchanged. Click it again.")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                }

                // A config edited by hand can still hold a collision.
                if model.dictateIsSubstituted {
                    Text("Input Monitoring is not granted, so “\(HotkeyConfig.symbolic(model.config.hotkey))” "
                       + "cannot be bound. Dictate is listening on the key above instead.")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                }

                if !model.clashing.isEmpty {
                    Text("\(model.clashing.joined(separator: " and ")) are on the same "
                       + "combination, so only one of them works. Click either and press "
                       + "a different one.")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                }
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        section("History", "What Rawi keeps of what you said, and for how long.") {
            VStack(alignment: .leading, spacing: 10) {
                picker(HistorySettings.retentionChoices.map { (String($0.days), $0.label) },
                       selected: String(model.config.history.retentionDays)) { raw in
                    model.config.history.retentionDays = Int(raw) ?? 90
                    model.save()
                }
                Text(model.config.history.retentionDays == 0
                     ? "Kept until there are \(model.config.history.limit) dictations, then the oldest go first."
                     : "Older dictations are deleted, along with any recording kept for a retry.")
                    .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                    .fixedSize(horizontal: false, vertical: true)
                Label(model.config.history.encrypted
                      ? "Encrypted on this Mac, with a key only your account can read, kept out of backups and search."
                      : "Stored as plain text. Set history.encrypted to true in config.json to seal it.",
                      systemImage: model.config.history.encrypted ? "lock.fill" : "lock.open")
                    .font(.system(size: TypeScale.small))
                    .foregroundStyle(model.config.history.encrypted ? c(.muted) : c(.clay))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        section("Transcription", "What turns your voice into text.") {
            VStack(alignment: .leading, spacing: 10) {
                picker(EngineKind.allCases.map { ($0.rawValue, engineName($0)) },
                       selected: model.config.engine.rawValue) { raw in
                    model.config.engine = EngineKind(rawValue: raw) ?? .whispercpp
                    model.save()
                }
                if model.config.engine == .whispercpp {
                    if model.whisperModels.isEmpty {
                        Text("No models found in \(ModelStore.directory.path)")
                            .font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                    } else {
                        picker(model.whisperModels.map {
                                   ($0.id, $0.multilingual ? $0.displayName
                                                           : "\($0.displayName) · English only")
                               },
                               selected: model.currentWhisperModel?.id ?? "") { id in
                            guard let picked = ModelStore.model(id: id) else { return }
                            model.config.whispercpp.model = ModelStore.url(for: picked).path
                            // An English-only model cannot hear Arabic at all, so the
                            // language setting follows the model rather than fighting it.
                            model.config.whispercpp.language = picked.multilingual ? "auto" : "en"
                            model.save()
                        }
                    }
                    if let current = model.currentWhisperModel, !current.multilingual {
                        // The failure this prevents is silent: an English-only model
                        // does not mishear Arabic, it cannot hear it at all.
                        Text("This model cannot transcribe Arabic. Choose a multilingual "
                           + "one if you dictate in both.")
                            .font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                    }
                } else {
                    Text("Audio leaves your machine with this engine. The key comes from "
                       + "~/.config/rawi/.env.")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.saffron))
                }
            }
        }
    }

    private func engineName(_ kind: EngineKind) -> String {
        switch kind {
        case .whispercpp: "whisper.cpp, on this Mac"
        case .groq: "Groq API"
        case .openai: "OpenAI API"
        }
    }

    // MARK: - Cleanup

    private var cleanupSection: some View {
        section("Cleanup and transforms", "The language model that removes fillers, fixes "
                                        + "punctuation, and runs transforms. Rewriting is harder "
                                        + "than cleaning, so anything that rewrites (polish, and "
                                        + "every transform) uses the larger model, whatever "
                                        + "language you spoke.") {
            VStack(alignment: .leading, spacing: 10) {
                picker(CleanupKind.allCases.map { ($0.rawValue, cleanupName($0)) },
                       selected: model.config.cleanup.provider.rawValue) { raw in
                    let kind = CleanupKind(rawValue: raw) ?? .off
                    model.config.cleanup.provider = kind
                    if kind != .off {
                        model.config.cleanup.models = CleanupProviderFactory.defaultModels(for: kind)
                        // A pinned model belongs to the provider it was pinned on:
                        // "gemma3:4b" is an Ollama name no hosted API has.
                        model.config.cleanup.transformModel = ""
                        model.config.cleanup.polishModel = ""
                    }
                    model.save()
                }

                switch model.config.cleanup.provider {
                case .off:
                    Text("Whisper's raw output is inserted, and transforms are unavailable.")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                case .ollama:
                    if !model.ollamaReachable {
                        Text("Ollama is not answering on localhost:11434.")
                            .font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                    }
                    // Named for what they actually govern. They used to read as
                    // "the English model" and "the Arabic model", which stopped
                    // being true when polish moved to the larger one: in polish
                    // mode an English dictation has not gone to the smaller model
                    // for some time, and a screen that says otherwise is worse
                    // than one that says nothing.
                    modelRow("Cleaning English and other Latin", keyPath: \.latin)
                    modelRow("Cleaning Arabic, and all rewriting", keyPath: \.arabic)
                    transformModelRow
                case .groq:
                    Text("Cleans in about half a second, with the same Groq key as "
                       + "transcription. The transcript goes to Groq, as the audio already "
                       + "does. Model: \(model.config.cleanup.models.latin)")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                    transformModelRow
                case .openai, .anthropic:
                    Text("Transcripts leave your machine with this provider. One model "
                       + "serves both scripts: \(model.config.cleanup.models.latin)")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.saffron))
                }
            }
        }
    }

    private func cleanupName(_ kind: CleanupKind) -> String {
        switch kind {
        case .off: "Off, insert exactly what was heard"
        case .ollama: "Ollama, on this Mac"
        case .groq: "Groq, fast (recommended)"
        case .openai: "OpenAI API"
        case .anthropic: "Anthropic API"
        }
    }

    /// Transforms write whole sentences, which is a different job from not
    /// changing your words. A model can be good at one and hopeless at the other.
    private var transformModelRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TRANSFORMS")
                .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                .tracking(1.1)
                .foregroundStyle(c(.faint))
            if model.installedOllama.isEmpty {
                Text(model.config.cleanup.transformModel.isEmpty
                     ? model.config.cleanup.models.arabic
                     : model.config.cleanup.transformModel)
                    .font(.system(size: TypeScale.small).monospaced())
                    .foregroundStyle(c(.muted))
            } else {
                picker(model.installedOllama.map { ($0, $0) },
                       selected: model.config.cleanup.transformModel.isEmpty
                           ? model.config.cleanup.models.arabic
                           : model.config.cleanup.transformModel) { picked in
                    model.config.cleanup.transformModel = picked
                    model.save()
                }
            }
            Text("Asked for Arabic, some models answer in Chinese. A rewrite that comes "
               + "back in the wrong language is refused and your clipboard is left alone.")
                .font(.system(size: TypeScale.small))
                .foregroundStyle(c(.faint))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modelRow(_ label: String,
                          keyPath: WritableKeyPath<CleanupModels, String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: TypeScale.micro, weight: .medium).monospaced()).tracking(1.1)
                .foregroundStyle(c(.faint))
            if model.installedOllama.isEmpty {
                Text(model.config.cleanup.models[keyPath: keyPath])
                    .font(.system(size: TypeScale.small).monospaced()).foregroundStyle(c(.muted))
            } else {
                picker(model.installedOllama.map { ($0, $0) },
                       selected: model.config.cleanup.models[keyPath: keyPath]) { picked in
                    model.config.cleanup.models[keyPath: keyPath] = picked
                    model.save()
                }
            }
        }
    }

    // MARK: - The file itself

    private var fileSection: some View {
        section("The file", "This screen does not cover everything. The cleanup prompt, "
                          + "the history cap and the excluded apps live in the file.") {
            HStack(spacing: 9) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: model.configPath))
                } label: {
                    Text("Open config.json").font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.ink))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.bone)))
                }.buttonStyle(.plain)
                Button { model.reload() } label: {
                    Text("Reload from disk").font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.muted))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.raised)))
                }.buttonStyle(.plain)
                Text(model.configPath)
                    .font(.system(size: TypeScale.small).monospaced()).foregroundStyle(c(.faint))
                    .lineLimit(1).truncationMode(.head)
            }
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, _ detail: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Text(detail).font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private func picker(_ options: [(String, String)], selected: String,
                        onPick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button(option.1) { onPick(option.0) }
            }
        } label: {
            HStack(spacing: 7) {
                Text(options.first { $0.0 == selected }?.1 ?? selected)
                    .font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: TypeScale.micro)).foregroundStyle(c(.faint))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
    }
}

/// A shortcut you set by pressing it.
///
/// The key monitor is local — it sees events only while this window has focus —
/// so it needs no permission, unlike the global monitors the hotkeys themselves
/// use. Escape cancels the capture rather than binding Escape.
struct HotkeyField: View {
    let raw: String
    let recording: Bool
    let clashes: Bool
    let appearance: ResolvedAppearance
    let onStart: () -> Void
    let onCapture: (String?) -> Void

    @State private var monitor: Any?
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    var body: some View {
        Button(action: onStart) {
            Text(recording ? "Press it now" : HotkeyConfig.symbolic(raw))
                .font(.system(size: TypeScale.body, weight: .medium).monospaced())
                .foregroundStyle(recording ? c(.saffron) : (clashes ? c(.clay) : c(.bone)))
                .frame(minWidth: 104)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(recording ? c(.saffron)
                                                : (clashes ? c(.clay) : c(.edge)))))
        }
        .buttonStyle(.plain)
        .help(recording ? "Press a combination, or a single ⌥, ⌘, ⌃ or fn. Escape keeps this one."
                        : "Click, then press the combination you want")
        .onChange(of: recording) { _, isRecording in
            isRecording ? start() : stop()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        stop()
        // A lone modifier never sends a key-down, only "modifiers changed". This
        // recorder used to listen for key-downs alone, so pressing ⌥ by itself
        // was never heard and the capture quietly timed out.
        var soloModifier: String?
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let held = event.modifierFlags.intersection([.command, .option, .control,
                                                             .shift, .function])
                if held.isEmpty {
                    // Everything let go. If one modifier went down and came back
                    // up with nothing else pressed, that modifier is the answer.
                    if let solo = soloModifier { onCapture(solo) }
                    soloModifier = nil
                } else if ([.command, .option, .control, .function] as [NSEvent.ModifierFlags]).contains(held) {
                    // Keep the first one pressed; a second one joining means a
                    // combination is coming, not a lone key.
                    if soloModifier == nil { soloModifier = HotkeyField.soloName(keyCode: event.keyCode) }
                } else {
                    soloModifier = nil
                }
                return event
            }
            soloModifier = nil
            if event.keyCode == HotkeyConfig.escapeKeyCode, event.modifierFlags.isEmpty {
                onCapture(nil)                       // keep what was there
                return nil
            }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            // A key that cannot be a shortcut is still an answer: saying why beats
            // waiting for the backstop to expire.
            onCapture(HotkeyConfig.string(keyCode: event.keyCode, modifiers: flags) ?? "")
            return nil                                // never let it reach the app
        }
    }

    /// The config name for a modifier key pressed on its own. Shift has none: it
    /// is not offered as a dictation key.
    static func soloName(keyCode: UInt16) -> String? {
        switch keyCode {
        case 58, 61: "option"
        case 55, 54: "command"
        case 59, 62: "control"
        case 63: "fn"
        default: nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
