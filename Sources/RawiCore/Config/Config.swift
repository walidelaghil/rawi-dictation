import Foundation

public enum EngineKind: String, Codable, Sendable, CaseIterable {
    case whispercpp, groq, openai
}

public enum CleanupKind: String, Codable, Sendable, CaseIterable {
    case openai, anthropic, ollama, off
}

public struct WhisperCppSettings: Codable, Sendable, Equatable {
    public var binary: String
    public var model: String
    public var language: String
    public var threads: Int
    /// Keep the model resident in a `whisper-server` instead of reloading it on
    /// every dictation. Worth 0.2 to 0.9 seconds each time, and removes the cold
    /// first dictation entirely.
    public var useServer: Bool
    public var serverPort: Int
    public var serverBinary: String
    /// A small model used only to answer "which language was that", so the real
    /// model can be told rather than having to work it out with a second encoder
    /// pass. Empty disables it and `auto` goes back to costing double.
    public var detectModel: String

    public init(binary: String, model: String, language: String, threads: Int,
                useServer: Bool = true, serverPort: Int = 8711,
                serverBinary: String = "whisper-server",
                detectModel: String = Config.defaultDetectModel) {
        self.binary = binary; self.model = model
        self.language = language; self.threads = threads
        self.useServer = useServer; self.serverPort = serverPort
        self.serverBinary = serverBinary; self.detectModel = detectModel
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultWhisperCpp
        binary = try c.decodeIfPresent(String.self, forKey: .binary) ?? d.binary
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? d.threads
        useServer = try c.decodeIfPresent(Bool.self, forKey: .useServer) ?? d.useServer
        serverPort = try c.decodeIfPresent(Int.self, forKey: .serverPort) ?? d.serverPort
        serverBinary = try c.decodeIfPresent(String.self, forKey: .serverBinary) ?? d.serverBinary
        detectModel = try c.decodeIfPresent(String.self, forKey: .detectModel) ?? d.detectModel
    }
}

public struct APISettings: Codable, Sendable, Equatable {
    public var groqModel: String
    public var openaiModel: String

    public init(groqModel: String, openaiModel: String) {
        self.groqModel = groqModel; self.openaiModel = openaiModel
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultAPI
        groqModel = try c.decodeIfPresent(String.self, forKey: .groqModel) ?? d.groqModel
        openaiModel = try c.decodeIfPresent(String.self, forKey: .openaiModel) ?? d.openaiModel
    }
}

/// Which cleanup model serves which script.
///
/// Not a preference — a correctness requirement. Measured on real transcripts:
/// `qwen2.5:1.5b` is faithful on English but *translates Arabic into English*
/// and cannot be instructed out of it; `qwen2.5:3b` is correct on Arabic and
/// mixed speech but leaves fillers in English. So each script gets the model
/// that does not break it.
public struct CleanupModels: Codable, Sendable, Equatable {
    public var latin: String
    public var arabic: String

    public init(latin: String, arabic: String) {
        self.latin = latin
        self.arabic = arabic
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultCleanup.models
        latin = try c.decodeIfPresent(String.self, forKey: .latin) ?? d.latin
        arabic = try c.decodeIfPresent(String.self, forKey: .arabic) ?? d.arabic
    }

    public func model(for script: Script) -> String {
        switch script {
        case .latin: latin
        case .arabic: arabic
        }
    }
}

public struct CleanupSettings: Codable, Sendable, Equatable {
    public var provider: CleanupKind
    public var models: CleanupModels
    /// The model transforms use. Separate from cleanup because the job is
    /// different: cleanup must not change your words, a transform must write whole
    /// sentences in a language you asked for, and a model can be good at one and
    /// hopeless at the other. Measured: qwen2.5:3b asked for Arabic answers in
    /// Chinese. Empty means "use the multilingual cleanup model".
    public var transformModel: String = ""
    public var prompt: String

    public init(provider: CleanupKind, models: CleanupModels, prompt: String,
                transformModel: String = "") {
        self.transformModel = transformModel
        self.provider = provider
        self.models = models
        self.prompt = prompt
    }

    private enum CodingKeys: String, CodingKey {
        case provider, models, prompt, transformModel
        case legacyModel = "model"     // v1 wrote a single model; read it, never write it
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultCleanup
        provider = try c.decodeIfPresent(CleanupKind.self, forKey: .provider) ?? d.provider
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? d.prompt

        transformModel = try c.decodeIfPresent(String.self, forKey: .transformModel) ?? ""
        if let explicit = try c.decodeIfPresent(CleanupModels.self, forKey: .models) {
            models = explicit
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .legacyModel) {
            // A v1 config only ever named an English-capable model, so it maps to latin.
            models = CleanupModels(latin: legacy, arabic: d.models.arabic)
        } else {
            models = d.models
        }
    }

    /// Explicit so the legacy `model` key is dropped on the next save rather than
    /// lingering as a second source of truth.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encode(models, forKey: .models)
        try c.encode(prompt, forKey: .prompt)
    }
}

public struct OutputSettings: Codable, Sendable, Equatable {
    public var restorePreviousClipboard: Bool
    public var restoreDelayMs: Int
    /// Put the raw transcript on the clipboard as soon as it exists, then upgrade
    /// it when cleanup finishes. Removes the cleanup wait from the time you spend
    /// unable to paste.
    public var deliverRawFirst: Bool = true

    public init(restorePreviousClipboard: Bool, restoreDelayMs: Int,
                deliverRawFirst: Bool = true) {
        self.restorePreviousClipboard = restorePreviousClipboard
        self.restoreDelayMs = restoreDelayMs
        self.deliverRawFirst = deliverRawFirst
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultOutput
        restorePreviousClipboard = try c.decodeIfPresent(
            Bool.self, forKey: .restorePreviousClipboard) ?? d.restorePreviousClipboard
        restoreDelayMs = try c.decodeIfPresent(Int.self, forKey: .restoreDelayMs) ?? d.restoreDelayMs
        deliverRawFirst = try c.decodeIfPresent(Bool.self, forKey: .deliverRawFirst)
            ?? d.deliverRawFirst
    }
}

public struct Config: Codable, Sendable, Equatable {
    public var appearance: Appearance
    public var hotkey: String
    public var doubleTapWindowMs: Int
    public var minHoldMs: Int
    public var maxSessionSeconds: Int
    public var maxPushToTalkSeconds: Int
    public var hotkeyBackend: HotkeyBackendKind
    public var fallbackHotkey: String
    public var cancelHotkey: String
    /// Hold to speak an instruction that rewrites whatever is on the clipboard.
    /// Registered through Carbon whichever backend dictation uses, because Carbon
    /// needs no permission — the transform key should not depend on one.
    public var transformHotkey: String
    public var engine: EngineKind
    public var whispercpp: WhisperCppSettings
    public var api: APISettings
    public var cleanup: CleanupSettings
    public var output: OutputSettings
    public var history: HistorySettings

    public init(appearance: Appearance = .system,
                hotkey: String, doubleTapWindowMs: Int, minHoldMs: Int,
                maxSessionSeconds: Int, maxPushToTalkSeconds: Int = 120,
                hotkeyBackend: HotkeyBackendKind = .auto,
                fallbackHotkey: String = "ctrl+option+space",
                cancelHotkey: String = "ctrl+option+escape",
                transformHotkey: String = "ctrl+option+t",
                engine: EngineKind,
                whispercpp: WhisperCppSettings, api: APISettings,
                cleanup: CleanupSettings, output: OutputSettings,
                history: HistorySettings = Config.defaultHistory) {
        self.appearance = appearance
        self.hotkey = hotkey
        self.doubleTapWindowMs = doubleTapWindowMs
        self.minHoldMs = minHoldMs
        self.maxSessionSeconds = maxSessionSeconds
        self.maxPushToTalkSeconds = maxPushToTalkSeconds
        self.hotkeyBackend = hotkeyBackend
        self.fallbackHotkey = fallbackHotkey
        self.cancelHotkey = cancelHotkey
        self.transformHotkey = transformHotkey
        self.engine = engine
        self.whispercpp = whispercpp
        self.api = api
        self.cleanup = cleanup
        self.output = output
        self.history = history
    }

    /// Tolerant decoding: a config missing any key still loads, filling from defaults.
    /// An *invalid* value for a present key still throws — a typo should be loud.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? d.hotkey
        doubleTapWindowMs = try c.decodeIfPresent(Int.self, forKey: .doubleTapWindowMs)
            ?? d.doubleTapWindowMs
        minHoldMs = try c.decodeIfPresent(Int.self, forKey: .minHoldMs) ?? d.minHoldMs
        maxSessionSeconds = try c.decodeIfPresent(Int.self, forKey: .maxSessionSeconds)
            ?? d.maxSessionSeconds
        maxPushToTalkSeconds = try c.decodeIfPresent(Int.self, forKey: .maxPushToTalkSeconds)
            ?? d.maxPushToTalkSeconds
        hotkeyBackend = try c.decodeIfPresent(HotkeyBackendKind.self, forKey: .hotkeyBackend)
            ?? d.hotkeyBackend
        fallbackHotkey = try c.decodeIfPresent(String.self, forKey: .fallbackHotkey)
            ?? d.fallbackHotkey
        cancelHotkey = try c.decodeIfPresent(String.self, forKey: .cancelHotkey) ?? d.cancelHotkey
        transformHotkey = try c.decodeIfPresent(String.self, forKey: .transformHotkey)
            ?? d.transformHotkey
        engine = try c.decodeIfPresent(EngineKind.self, forKey: .engine) ?? d.engine
        whispercpp = try c.decodeIfPresent(WhisperCppSettings.self, forKey: .whispercpp)
            ?? d.whispercpp
        api = try c.decodeIfPresent(APISettings.self, forKey: .api) ?? d.api
        cleanup = try c.decodeIfPresent(CleanupSettings.self, forKey: .cleanup) ?? d.cleanup
        output = try c.decodeIfPresent(OutputSettings.self, forKey: .output) ?? d.output
        history = try c.decodeIfPresent(HistorySettings.self, forKey: .history) ?? d.history
    }

    // MARK: - Defaults

    /// The detector's model. Small on purpose: it answers one question and the
    /// answer is a language code.
    public static var defaultDetectModel: String {
        Config.supportDirectory.appendingPathComponent("models/ggml-base.bin").path
    }

    public static let defaultWhisperCpp = WhisperCppSettings(
        binary: "whisper-cli",
        // Multilingual, always. The v1 English-only model did not degrade on
        // Arabic — it failed outright.
        model: Config.supportDirectory
            .appendingPathComponent("models/ggml-large-v3-turbo-q5_0.bin").path,
        language: "auto",
        threads: 8)

    public static let defaultAPI = APISettings(
        groqModel: "whisper-large-v3-turbo",
        openaiModel: "whisper-1")

    public static let defaultCleanup = CleanupSettings(
        provider: .off,
        models: CleanupModels(latin: "qwen2.5:1.5b", arabic: "qwen2.5:3b"),
        prompt: defaultCleanupPrompt)

    public static let defaultOutput = OutputSettings(
        restorePreviousClipboard: false,
        restoreDelayMs: 300,
        deliverRawFirst: true)

    public static let defaultHistory = HistorySettings(
        enabled: true,
        limit: 500,
        excludedBundleIDs: ["1password", "com.apple.MobileSMS", "com.apple.iChat",
                            "keychain", "com.lastpass", "com.bitwarden"])

    public static let `default` = Config(
        appearance: .system,
        hotkey: "fn",
        doubleTapWindowMs: 350,
        minHoldMs: 250,
        maxSessionSeconds: 300,
        maxPushToTalkSeconds: 120,
        hotkeyBackend: .auto,
        fallbackHotkey: "ctrl+option+space",
        cancelHotkey: "ctrl+option+escape",
        transformHotkey: "ctrl+option+t",
        engine: .whispercpp,
        whispercpp: defaultWhisperCpp,
        api: defaultAPI,
        cleanup: defaultCleanup,
        output: defaultOutput,
        history: defaultHistory)

    /// The dictation key that is actually listening.
    ///
    /// `hotkey` is what you asked for; on a Mac that cannot grant Input Monitoring
    /// the Carbon backend cannot bind a bare modifier and substitutes
    /// `fallbackHotkey`. Every screen that prints a shortcut has to print this one,
    /// or it teaches a gesture that does nothing on the machine it is running on.
    public func effectiveDictateHotkey(inputMonitoringGranted: Bool) -> String {
        switch hotkeyBackend.resolved(inputMonitoringGranted: inputMonitoringGranted) {
        case .carbon:
            return HotkeyConfig.isCarbonCompatible(hotkey) ? hotkey : fallbackHotkey
        case .eventTap, .auto:
            return hotkey
        }
    }

    // MARK: - Locations

    public static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/rawi", isDirectory: true)
    }

    public static var configFile: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    public static var envFile: URL {
        configDirectory.appendingPathComponent(".env")
    }

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Rawi", isDirectory: true)
    }

    public static var recordingsDirectory: URL {
        supportDirectory.appendingPathComponent("recordings", isDirectory: true)
    }

    // MARK: - Persistence

    public static func load(from url: URL = Config.configFile) throws -> Config {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func save(to url: URL = Config.configFile) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// True when the local engine is selected but its model is not on disk.
    /// An unknown path counts as missing — we cannot vouch for a file we do not know.
    public var needsModelDownload: Bool {
        guard engine == .whispercpp else { return false }
        guard let model = ModelStore.model(forPath: whispercpp.model) else { return true }
        return !ModelStore.isInstalled(model)
    }

    /// Expands a leading `~` in a configured path.
    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
