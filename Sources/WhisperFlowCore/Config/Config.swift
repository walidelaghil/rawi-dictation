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

    public init(binary: String, model: String, language: String, threads: Int) {
        self.binary = binary; self.model = model
        self.language = language; self.threads = threads
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultWhisperCpp
        binary = try c.decodeIfPresent(String.self, forKey: .binary) ?? d.binary
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? d.threads
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

public struct CleanupSettings: Codable, Sendable, Equatable {
    public var provider: CleanupKind
    public var model: String
    public var prompt: String

    public init(provider: CleanupKind, model: String, prompt: String) {
        self.provider = provider; self.model = model; self.prompt = prompt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultCleanup
        provider = try c.decodeIfPresent(CleanupKind.self, forKey: .provider) ?? d.provider
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? d.prompt
    }
}

public struct OutputSettings: Codable, Sendable, Equatable {
    public var restorePreviousClipboard: Bool
    public var restoreDelayMs: Int

    public init(restorePreviousClipboard: Bool, restoreDelayMs: Int) {
        self.restorePreviousClipboard = restorePreviousClipboard
        self.restoreDelayMs = restoreDelayMs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultOutput
        restorePreviousClipboard = try c.decodeIfPresent(
            Bool.self, forKey: .restorePreviousClipboard) ?? d.restorePreviousClipboard
        restoreDelayMs = try c.decodeIfPresent(Int.self, forKey: .restoreDelayMs) ?? d.restoreDelayMs
    }
}

public struct Config: Codable, Sendable, Equatable {
    public var hotkey: String
    public var doubleTapWindowMs: Int
    public var minHoldMs: Int
    public var maxSessionSeconds: Int
    public var maxPushToTalkSeconds: Int
    public var hotkeyBackend: HotkeyBackendKind
    public var fallbackHotkey: String
    public var cancelHotkey: String
    public var engine: EngineKind
    public var whispercpp: WhisperCppSettings
    public var api: APISettings
    public var cleanup: CleanupSettings
    public var output: OutputSettings

    public init(hotkey: String, doubleTapWindowMs: Int, minHoldMs: Int,
                maxSessionSeconds: Int, maxPushToTalkSeconds: Int = 120,
                hotkeyBackend: HotkeyBackendKind = .auto,
                fallbackHotkey: String = "ctrl+option+space",
                cancelHotkey: String = "ctrl+option+escape",
                engine: EngineKind,
                whispercpp: WhisperCppSettings, api: APISettings,
                cleanup: CleanupSettings, output: OutputSettings) {
        self.hotkey = hotkey
        self.doubleTapWindowMs = doubleTapWindowMs
        self.minHoldMs = minHoldMs
        self.maxSessionSeconds = maxSessionSeconds
        self.maxPushToTalkSeconds = maxPushToTalkSeconds
        self.hotkeyBackend = hotkeyBackend
        self.fallbackHotkey = fallbackHotkey
        self.cancelHotkey = cancelHotkey
        self.engine = engine
        self.whispercpp = whispercpp
        self.api = api
        self.cleanup = cleanup
        self.output = output
    }

    /// Tolerant decoding: a config missing any key still loads, filling from defaults.
    /// An *invalid* value for a present key still throws — a typo should be loud.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
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
        engine = try c.decodeIfPresent(EngineKind.self, forKey: .engine) ?? d.engine
        whispercpp = try c.decodeIfPresent(WhisperCppSettings.self, forKey: .whispercpp)
            ?? d.whispercpp
        api = try c.decodeIfPresent(APISettings.self, forKey: .api) ?? d.api
        cleanup = try c.decodeIfPresent(CleanupSettings.self, forKey: .cleanup) ?? d.cleanup
        output = try c.decodeIfPresent(OutputSettings.self, forKey: .output) ?? d.output
    }

    // MARK: - Defaults

    public static let defaultWhisperCpp = WhisperCppSettings(
        binary: "whisper-cli",
        model: Config.supportDirectory
            .appendingPathComponent("models/ggml-small.en.bin").path,
        language: "en",
        threads: 8)

    public static let defaultAPI = APISettings(
        groqModel: "whisper-large-v3-turbo",
        openaiModel: "whisper-1")

    public static let defaultCleanup = CleanupSettings(
        provider: .off,
        model: "qwen2.5:1.5b",
        prompt: defaultCleanupPrompt)

    public static let defaultOutput = OutputSettings(
        restorePreviousClipboard: false,
        restoreDelayMs: 300)

    public static let `default` = Config(
        hotkey: "fn",
        doubleTapWindowMs: 350,
        minHoldMs: 250,
        maxSessionSeconds: 300,
        maxPushToTalkSeconds: 120,
        hotkeyBackend: .auto,
        fallbackHotkey: "ctrl+option+space",
        cancelHotkey: "ctrl+option+escape",
        engine: .whispercpp,
        whispercpp: defaultWhisperCpp,
        api: defaultAPI,
        cleanup: defaultCleanup,
        output: defaultOutput)

    // MARK: - Locations

    public static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/whisperflow", isDirectory: true)
    }

    public static var configFile: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    public static var envFile: URL {
        configDirectory.appendingPathComponent(".env")
    }

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperFlow", isDirectory: true)
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

    /// Expands a leading `~` in a configured path.
    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
