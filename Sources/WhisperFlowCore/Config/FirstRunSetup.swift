import Foundation

/// What the environment actually offers. Separated from detection so the rules
/// can be tested without touching the network or the filesystem.
public struct Probes: Sendable, Equatable {
    public var envKeys: Set<String>
    public var ollamaReachable: Bool
    public var whisperBinaryFound: Bool
    public var whisperModelFound: Bool

    public init(envKeys: Set<String>, ollamaReachable: Bool,
                whisperBinaryFound: Bool, whisperModelFound: Bool) {
        self.envKeys = envKeys
        self.ollamaReachable = ollamaReachable
        self.whisperBinaryFound = whisperBinaryFound
        self.whisperModelFound = whisperModelFound
    }
}

public enum FirstRunSetup {
    /// Chooses a working configuration from what is available, preferring local
    /// and free over hosted and paid.
    public static func detect(_ p: Probes) -> Config {
        var config = Config.default

        config.engine =
            if p.whisperBinaryFound && p.whisperModelFound { .whispercpp }
            else if p.envKeys.contains("GROQ_API_KEY") { .groq }
            else if p.envKeys.contains("OPENAI_API_KEY") { .openai }
            else { .whispercpp }          // menu bar will flag the missing model

        let cleanupKind: CleanupKind =
            if p.envKeys.contains("OPENAI_API_KEY") { .openai }
            else if p.envKeys.contains("ANTHROPIC_API_KEY") { .anthropic }
            else if p.ollamaReachable { .ollama }
            else { .off }

        config.cleanup.provider = cleanupKind
        if cleanupKind != .off {
            config.cleanup.model = CleanupProviderFactory.defaultModel(for: cleanupKind)
        }
        return config
    }

    /// Probes the live machine. The Ollama check is deliberately short-timeout so a
    /// first launch is never held up by a service that is not running.
    public static func liveProbes(env: DotEnv) async -> Probes {
        let binary = WhisperCppEngine.resolveBinary(Config.defaultWhisperCpp.binary) != nil
        let model = FileManager.default.fileExists(
            atPath: Config.expand(Config.defaultWhisperCpp.model))
        return Probes(envKeys: env.keys,
                      ollamaReachable: await isOllamaReachable(),
                      whisperBinaryFound: binary,
                      whisperModelFound: model)
    }

    static func isOllamaReachable(timeout: TimeInterval = 0.5) async -> Bool {
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        request.timeoutInterval = timeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: configuration)
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Loads config, creating a detected one on first launch.
    /// Returns the config and whether it was just created.
    public static func loadOrCreate() async -> (config: Config, created: Bool) {
        let env = DotEnv.load(from: Config.envFile)
        if let existing = try? Config.load() {
            return (existing, false)
        }
        let detected = detect(await liveProbes(env: env))
        try? detected.save()
        return (detected, true)
    }
}
