import Foundation

/// Everything a first run has to get right, checked in one place.
///
/// The setup screen, the menu bar and the doctor all ask the same questions. One
/// answer means they cannot disagree about whether Rawi is ready.
public struct SetupStatus: Sendable, Equatable {
    public var microphone: Bool
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var whisperInstalled: Bool
    public var transcriptionModel: Bool
    public var detectorModel: Bool
    public var ollamaReachable: Bool
    public var ollamaMissing: [String]

    public init(microphone: Bool, accessibility: Bool, inputMonitoring: Bool,
                whisperInstalled: Bool, transcriptionModel: Bool, detectorModel: Bool,
                ollamaReachable: Bool, ollamaMissing: [String]) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.whisperInstalled = whisperInstalled
        self.transcriptionModel = transcriptionModel
        self.detectorModel = detectorModel
        self.ollamaReachable = ollamaReachable
        self.ollamaMissing = ollamaMissing
    }

    /// Enough to dictate at all. Everything else makes it better, not possible.
    public var canDictate: Bool { microphone && whisperInstalled && transcriptionModel }

    /// Polish and transforms are optional, but only once decided: either Ollama is
    /// ready, or cleanup is off.
    public func polishReady(provider: CleanupKind) -> Bool {
        provider != .ollama || (ollamaReachable && ollamaMissing.isEmpty)
    }

    public static func current(config: Config) async -> SetupStatus {
        let permissions = Permissions.current()
        let transcription = config.engine != .whispercpp
            || ModelStore.model(forPath: config.whispercpp.model).map(ModelStore.isInstalled)
            ?? FileManager.default.fileExists(atPath: Config.expand(config.whispercpp.model))
        let detector = config.whispercpp.language != "auto"
            || FileManager.default.fileExists(atPath: Config.expand(config.whispercpp.detectModel))
        // Both binaries, not just the command line: with `useServer` on it is
        // `whisper-server` that every dictation needs, and checking only
        // `whisper-cli` let setup report a clean install while the pill said
        // whisper.cpp was not installed.
        let cli = ToolBinary.resolve(config.whispercpp.binary) != nil
        let server = !config.whispercpp.useServer
            || ToolBinary.resolve(config.whispercpp.serverBinary) != nil
        let whisper = config.engine != .whispercpp || (cli && server)
        var reachable = false
        var missing: [String] = []
        if config.cleanup.provider == .ollama {
            reachable = await OllamaModels.isReachable()
            if reachable {
                let have = await OllamaModels.installedNames()
                missing = OllamaModels.required(for: config).map(\.name).filter { !have.contains($0) }
            } else {
                missing = OllamaModels.required(for: config).map(\.name)
            }
        }
        return SetupStatus(microphone: permissions.microphone,
                           accessibility: permissions.accessibility,
                           inputMonitoring: permissions.inputMonitoring,
                           whisperInstalled: whisper, transcriptionModel: transcription,
                           detectorModel: detector, ollamaReachable: reachable,
                           ollamaMissing: missing)
    }
}


/// One line of the "Complete setup" list.
public struct SetupChecklistItem: Identifiable, Sendable, Equatable {
    /// The step alone is not unique: the speech model and the language detector are
    /// both fixed on the same step, and sharing an id made the list draw one of them
    /// twice.
    public var id: String { "\(step.rawValue)-\(title)" }
    public let step: SetupStep
    public let title: String
    /// What is missing, when something is.
    public let detail: String
    public let done: Bool
    /// Rawi cannot dictate without it.
    public let required: Bool
}

/// What is still to do, from the same checks setup runs.
///
/// Skipping a step used to leave no trace: you found out at the next dictation,
/// through an error naming a file path. Worse, polish left half-configured (turned
/// on, models not downloaded) failed silently on every dictation and said so only
/// in the log. This is the one place that knows, and the window and the menu both
/// read it.
public struct SetupChecklist: Sendable, Equatable {
    public let items: [SetupChecklistItem]

    public var outstanding: [SetupChecklistItem] { items.filter { !$0.done } }
    public var isComplete: Bool { outstanding.isEmpty }
    /// Something Rawi cannot work without.
    public var isBlocked: Bool { outstanding.contains(where: \.required) }

    public static func make(status: SetupStatus, config: Config) -> SetupChecklist {
        var items: [SetupChecklistItem] = [
            SetupChecklistItem(step: .microphone, title: "Microphone",
                               detail: "Rawi cannot hear you until this is allowed.",
                               done: status.microphone, required: true),
            SetupChecklistItem(step: .paste, title: "Typing for you",
                               detail: "Without Accessibility, Rawi copies and you press ⌘V. "
                                     + "Learning spellings from your corrections is off too.",
                               done: status.accessibility, required: false),
            SetupChecklistItem(step: .models, title: "Speech model",
                               detail: status.whisperInstalled
                                   ? "The model is not downloaded yet."
                                   : "whisper.cpp is not installed yet.",
                               done: status.whisperInstalled && status.transcriptionModel,
                               required: true),
        ]
        if config.whispercpp.language == "auto", config.engine == .whispercpp {
            items.append(SetupChecklistItem(
                step: .models, title: "Language detector",
                detail: "One key for English and Arabic needs the small detector model.",
                done: status.detectorModel, required: false))
        }
        // Polish counts as done when it is off: that is a choice, not a gap. When it
        // is on, it has to actually work.
        if config.cleanup.provider == .ollama {
            items.append(SetupChecklistItem(
                step: .polish, title: "Polish",
                detail: status.ollamaReachable
                    ? "Polish is on, but \(status.ollamaMissing.joined(separator: ", ")) "
                      + "\(status.ollamaMissing.count == 1 ? "is" : "are") not downloaded, so "
                      + "Rawi is typing what it heard."
                    : "Polish is on, but Ollama is not running, so Rawi is typing what it heard.",
                done: status.polishReady(provider: .ollama), required: false))
        }
        return SetupChecklist(items: items)
    }
}
