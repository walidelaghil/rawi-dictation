import AppKit
import SwiftUI

/// The steps of a first run, in the order they are needed.
public enum SetupStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome, microphone, paste, models, polish, hotkey, tryIt
    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .microphone: "Microphone"
        case .paste: "Typing for you"
        case .models: "Speech model"
        case .polish: "Polish"
        case .hotkey: "Your key"
        case .tryIt: "Try it"
        }
    }
}

@MainActor
public final class SetupViewModel: ObservableObject {
    @Published public var step: SetupStep = .welcome
    @Published public var status: SetupStatus?
    @Published public var appearance: ResolvedAppearance = .dark
    /// Download progress by model id or Ollama name, 0...1.
    @Published public var progress: [String: Double] = [:]
    @Published public var problem: String?
    @Published public var tryText = ""
    /// Whether the key listener was started with Input Monitoring. A grant made
    /// during setup only reaches the listener after a restart.
    public var launchedWithInputMonitoring = Permissions.current().inputMonitoring

    public let settings: SettingsViewModel
    public var onFinish: (() -> Void)?
    public var onRestart: (() -> Void)?
    private var poller: Timer?

    public init(settings: SettingsViewModel = SettingsViewModel()) {
        self.settings = settings
        settings.reload()
    }

    public var config: Config { settings.config }

    public func refresh() async {
        status = await SetupStatus.current(config: settings.config)
    }

    /// Permissions are granted in System Settings, so the screen keeps looking.
    public func startPolling() {
        guard poller == nil else { return }
        Task { await refresh() }
        poller = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let model = self
                Task { @MainActor in await model?.refresh() }
            }
        }
    }

    public func stopPolling() {
        poller?.invalidate()
        poller = nil
    }

    public func isDone(_ step: SetupStep) -> Bool {
        guard let status else { return false }
        switch step {
        case .welcome: return self.step.rawValue > SetupStep.welcome.rawValue
        case .microphone: return status.microphone
        case .paste: return status.accessibility
        case .models: return status.whisperInstalled && status.transcriptionModel && status.detectorModel
        case .polish: return status.polishReady(provider: config.cleanup.provider)
        case .hotkey: return self.step.rawValue > SetupStep.hotkey.rawValue
        case .tryIt: return !tryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func next() {
        if let following = SetupStep(rawValue: step.rawValue + 1) { step = following } else { finish() }
    }

    public func back() {
        if let previous = SetupStep(rawValue: step.rawValue - 1) { step = previous }
    }

    public func finish() {
        settings.config.setupCompleted = true
        settings.save()
        stopPolling()
        onFinish?()
    }

    // MARK: Actions

    public func allowMicrophone() {
        Task {
            _ = await Permissions.requestMicrophone()
            await refresh()
        }
    }

    public func allowAccessibility() {
        Permissions.requestAccessibilityPrompt()
        Permissions.openSettings(for: .accessibility)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    public func allowInputMonitoring() {
        _ = Permissions.requestInputMonitoring()
        Permissions.openSettings(for: .inputMonitoring)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    public var needsRestartForKey: Bool {
        (status?.inputMonitoring ?? false) && !launchedWithInputMonitoring
    }

    /// The models this configuration needs and does not have.
    public var missingModels: [WhisperModel] {
        var list: [WhisperModel] = []
        if let status, !status.transcriptionModel,
           let model = ModelStore.model(forPath: config.whispercpp.model) ?? Optional(ModelStore.recommended) {
            list.append(model)
        }
        if let status, !status.detectorModel { list.append(ModelStore.detector) }
        return list
    }

    public func downloadModels() {
        let models = missingModels
        guard !models.isEmpty else { return }
        problem = nil
        Task {
            for model in models {
                progress[model.id] = 0
                do {
                    let destination = try await ModelStore.download(model) { fraction in
                        Task { @MainActor in self.progress[model.id] = fraction }
                    }
                    if model.id != ModelStore.detector.id, ModelStore.model(forPath: config.whispercpp.model) == nil {
                        settings.config.whispercpp.model = destination.path
                        settings.save()
                    }
                } catch {
                    problem = "\(model.displayName) did not download: \(error.localizedDescription)"
                    progress[model.id] = nil
                    return
                }
                progress[model.id] = nil
            }
            await refresh()
        }
    }

    /// Turns polish on with the local defaults, for a first run that found Ollama.
    public func usePolish() {
        settings.config.cleanup.provider = .ollama
        settings.config.cleanup.models = CleanupProviderFactory.defaultModels(for: .ollama)
        if settings.config.cleanup.transformModel.isEmpty { settings.config.cleanup.transformModel = "gemma3:4b" }
        settings.save()
        Task { await refresh() }
    }

    public func skipPolish() {
        settings.config.cleanup.provider = .off
        settings.save()
        Task { await refresh() }
        next()
    }

    public func pullOllamaModels() {
        guard let missing = status?.ollamaMissing, !missing.isEmpty else { return }
        problem = nil
        Task {
            for name in missing {
                progress[name] = 0
                do {
                    try await OllamaModels.pull(name) { fraction in
                        Task { @MainActor in self.progress[name] = fraction }
                    }
                } catch {
                    problem = "\(name) did not download: \(error.localizedDescription)"
                    progress[name] = nil
                    return
                }
                progress[name] = nil
            }
            await refresh()
        }
    }
}

public struct SetupView: View {
    @ObservedObject var model: SetupViewModel
    @ObservedObject var settings: SettingsViewModel
    @FocusState private var tryFocused: Bool

    public init(model: SetupViewModel) {
        self.model = model
        self.settings = model.settings
    }

    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(c(.edge)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(.horizontal, 32).padding(.top, 34).padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
            .background(c(.surface))
        }
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RawiMarkShape()
                    .stroke(c(.saffron), style: RawiMarkShape.stroke(for: 20))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Wordmark(appearance: model.appearance)
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 20)

            ForEach(SetupStep.allCases) { step in
                Button { model.step = step } label: {
                    HStack(spacing: 10) {
                        stepMark(step)
                        Text(step.title)
                            .font(.system(size: TypeScale.body, weight: model.step == step ? .semibold : .regular))
                            .foregroundStyle(model.step == step ? c(.bone) : c(.muted))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.control)
                        .fill(model.step == step ? c(.raised) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Skip setup") { model.finish() }
                .buttonStyle(.plain)
                .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                .padding(10)
                .help("You can open setup again from the menu bar")
        }
        .padding(12)
        .frame(width: 214)
        .background(c(.ink))
    }

    @ViewBuilder private func stepMark(_ step: SetupStep) -> some View {
        if model.isDone(step) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(c(.verdigris))
                .font(.system(size: TypeScale.heading))
        } else if model.step == step {
            Circle().fill(c(.saffron)).frame(width: 8, height: 8).frame(width: 15, height: 15)
        } else {
            Circle().strokeBorder(c(.edge), lineWidth: 1.5).frame(width: 13, height: 13)
                .frame(width: 15, height: 15)
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: welcome
        case .microphone: microphone
        case .paste: paste
        case .models: models
        case .polish: polish
        case .hotkey: hotkey
        case .tryIt: tryIt
        }
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: TypeScale.title, weight: .semibold)).foregroundStyle(c(.bone))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(.bottom, 18)
    }

    private func item(_ title: String, _ detail: String, done: Bool, required: Bool = false,
                      @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : (required ? "circle" : "circle.dashed"))
                .font(.system(size: TypeScale.heading))
                .foregroundStyle(done ? c(.verdigris) : (required ? c(.saffron) : c(.faint)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: TypeScale.body, weight: .medium)).foregroundStyle(c(.bone))
                Text(detail).font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if !done { action() }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private func primary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Dark ink on the bright dark-mode saffron; white on the deeper light-mode
            // saffron. One text colour for both failed contrast in light.
            Text(title).font(.system(size: TypeScale.body, weight: .semibold))
                .foregroundStyle(model.appearance == .dark ? RawiColors.color(.ink, .dark)
                                                           : RawiColors.color(.surface, .light))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.saffron)))
        }.buttonStyle(.plain)
    }

    private func secondary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
        }.buttonStyle(.plain)
    }

    private func bar(_ fraction: Double) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: fraction).tint(c(.saffron)).frame(width: 110)
            Text("\(Int(fraction * 100))%").font(.system(size: TypeScale.small).monospacedDigit())
                .foregroundStyle(c(.muted)).frame(width: 34, alignment: .trailing)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Speak, and it types.",
                    "Hold a key anywhere on your Mac, talk in English or Arabic or both, and let go. "
                  + "Rawi writes what you meant into whatever you are typing in. Everything runs on "
                  + "this Mac: your voice never leaves it.")
            item("A few minutes", "Setup asks for two permissions and downloads the speech model.",
                 done: false)
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Let Rawi hear you.",
                    "Rawi listens only while you hold your key, and the recording is deleted once it is "
                  + "transcribed.")
            item("Microphone", "Required to dictate.", done: model.status?.microphone ?? false,
                 required: true) { primary("Allow", model.allowMicrophone) }
        }
    }

    private var paste: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Let Rawi type for you.",
                    "With Accessibility, Rawi puts your words straight into the text field you are in. "
                  + "Without it, it copies them and you press ⌘V. It also lets Rawi learn a spelling when "
                  + "you correct one.")
            item("Accessibility", "Recommended. Opens System Settings: turn Rawi on in the list.",
                 done: model.status?.accessibility ?? false) { primary("Open Settings", model.allowAccessibility) }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 12) {
            let turbo = ModelStore.model(forPath: model.config.whispercpp.model) ?? ModelStore.recommended
            heading("Download the speech model.",
                    "Transcription runs on this Mac with whisper.cpp. The model is \(turbo.approxSize) "
                  + "and a small language detector \(ModelStore.detector.approxSize), downloaded once.")
            let status = model.status
            item("whisper.cpp",
                 status?.whisperInstalled == true ? "Installed." : "Install it in Terminal with: brew install whisper-cpp",
                 done: status?.whisperInstalled ?? false, required: true) {
                secondary("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install whisper-cpp", forType: .string)
                }
            }
            item(turbo.displayName, "Transcribes English and Arabic. \(turbo.approxSize).",
                 done: status?.transcriptionModel ?? false, required: true) {
                if let fraction = model.progress[turbo.id] { bar(fraction) }
            }
            item("Language detector", "Lets one key work for both languages. \(ModelStore.detector.approxSize).",
                 done: status?.detectorModel ?? false, required: true) {
                if let fraction = model.progress[ModelStore.detector.id] { bar(fraction) }
            }
            if !model.missingModels.isEmpty, model.progress.isEmpty {
                primary("Download", model.downloadModels)
            }
            problemText
        }
    }

    private var polish: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Polish what you say.",
                    "A small language model on this Mac removes filler, applies the corrections you speak "
                  + "(\u{201C}Monday, no, Tuesday\u{201D}) and turns run-on speech into sentences. It needs "
                  + "Ollama. You can skip this and Rawi types exactly what it heard.")
            let status = model.status
            if model.config.cleanup.provider != .ollama {
                item("Ollama", status?.ollamaReachable == true ? "Running on this Mac." : "Not found. Install it from ollama.com, open it, then come back.",
                     done: false) {
                    secondary("Get Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
                }
                HStack(spacing: 10) {
                    primary("Use polish", model.usePolish)
                    secondary("Skip", model.skipPolish)
                }
            } else if status?.ollamaReachable != true {
                item("Ollama", "Not running. Install it from ollama.com or open it, and this updates on its own.",
                     done: false, required: true) {
                    secondary("Get Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
                }
                secondary("Skip polish", model.skipPolish)
            } else {
                ForEach(OllamaModels.required(for: model.config), id: \.name) { required in
                    item(required.name, "For \(required.purpose).",
                         done: !(status?.ollamaMissing.contains(required.name) ?? true), required: true) {
                        if let fraction = model.progress[required.name] { bar(fraction) }
                    }
                }
                if !(status?.ollamaMissing.isEmpty ?? true), model.progress.isEmpty {
                    primary("Download models", model.pullOllamaModels)
                }
            }
            problemText
        }
    }

    private var hotkey: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Choose your key.",
                    "Hold it while you speak, let go to type. Tap it twice to keep listening hands-free, "
                  + "and tap once more to stop.")
            HStack(spacing: 12) {
                Text("Dictate").font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                HotkeyField(raw: settings.value(for: .dictate),
                            recording: settings.recording == SettingsViewModel.Key.dictate.rawValue,
                            clashes: settings.clashes(.dictate),
                            appearance: model.appearance,
                            onStart: { settings.beginCapture(.dictate) },
                            onCapture: { raw in
                                settings.endCapture()
                                if let raw { settings.assign(raw, to: .dictate) }
                            })
                Spacer()
            }
            if let problem = settings.captureProblem {
                Text(problem).font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
            }
            item("Input Monitoring", "Needed only for a single key on its own, like ⌥ or fn. Combinations work without it.",
                 done: model.status?.inputMonitoring ?? false) { secondary("Open Settings", model.allowInputMonitoring) }
            if model.needsRestartForKey {
                HStack(spacing: 10) {
                    Text("Restart Rawi so it can listen for a single key.")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                    secondary("Restart Rawi") { model.onRestart?() }
                }
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Try it.",
                    "Click in the box, hold \(HotkeyConfig.symbolic(settings.value(for: .dictate))) and say something. "
                  + "Let go, and your words appear here.")
            TextEditor(text: $model.tryText)
                .font(.system(size: TypeScale.heading))
                .foregroundStyle(c(.bone))
                .scrollContentBackground(.hidden)
                .focused($tryFocused)
                .padding(12)
                .frame(minHeight: 140)
                .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.ink))
                    .overlay(RoundedRectangle(cornerRadius: Radius.surface)
                        .strokeBorder(tryFocused ? c(.saffron) : c(.edge))))
                .onAppear { tryFocused = true }
            if !(model.status?.canDictate ?? false) {
                Text("Dictation is not ready yet: finish the microphone and speech model steps first.")
                    .font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
            }
        }
    }

    @ViewBuilder private var problemText: some View {
        if let problem = model.problem {
            Text(problem).font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.step != .welcome { secondary("Back", model.back) }
            Spacer()
            primary(model.step == .tryIt ? "Finish" : (model.step == .welcome ? "Get started" : "Continue"),
                    model.next)
        }
        .padding(.horizontal, 32).padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(c(.edge)).frame(height: 1) }
    }
}

/// The window setup lives in.
@MainActor
public final class SetupWindow: NSObject, NSWindowDelegate {
    public let model: SetupViewModel
    private var window: NSWindow?

    public init(model: SetupViewModel = SetupViewModel()) {
        self.model = model
        super.init()
    }

    public func show(appearance: ResolvedAppearance) {
        model.appearance = appearance
        let window = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Set up Rawi"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SetupView(model: model))
            w.center()
            return w
        }()
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() { window?.close() }

    public func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }
}
