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
        let whisper = config.engine != .whispercpp
            || WhisperCppEngine.resolveBinary(config.whispercpp.binary) != nil
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
