import Foundation

public protocol CleanupProvider: AnyObject, Sendable {
    /// `instruction` shapes this one dictation for where it is going. It is a
    /// per-call argument rather than provider state because the destination
    /// changes with every key-press while the provider is built once.
    func clean(_ transcript: String, instruction: String) async throws -> String
    /// The same job, on the strongest model available, for a dictation whose
    /// *shape* has to survive and not only its words.
    func cleanKeepingShape(_ transcript: String, instruction: String) async throws -> String
    func cancel()
    /// Gets the model ready while you are still speaking. See `ChatCleanup.warm`.
    func warm() async
}

public extension CleanupProvider {
    func warm() async {}

    /// A provider with one model has no stronger one to offer.
    func cleanKeepingShape(_ transcript: String, instruction: String) async throws -> String {
        try await clean(transcript, instruction: instruction)
    }

    func clean(_ transcript: String) async throws -> String {
        try await clean(transcript, instruction: "")
    }
}

public enum CleanupError: Error, LocalizedError, Equatable {
    case missingAPIKey(String)
    case badResponse(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let k): "Missing \(k) in ~/.config/rawi/.env"
        case .badResponse(let m): "Cleanup provider returned an unexpected response: \(m)"
        case .cancelled: "Cancelled"
        }
    }
}

/// Used when `cleanup.provider` is `off`. Returns the transcript untouched.
public final class NoopCleanup: CleanupProvider {
    public init() {}
    public func clean(_ transcript: String, instruction: String) async throws -> String {
        transcript
    }
    public func cancel() {}
}

public enum CleanupProviderFactory {
    public static func make(config: Config, env: DotEnv) throws -> any CleanupProvider {
        switch config.cleanup.provider {
        case .off:
            return NoopCleanup()
        case .ollama:
            return RoutedCleanup(kind: .ollama, apiKey: nil, models: config.cleanup.models,
                                 prompt: config.cleanup.prompt)
        case .openai:
            guard let key = env["OPENAI_API_KEY"], !key.isEmpty else {
                throw CleanupError.missingAPIKey("OPENAI_API_KEY")
            }
            return RoutedCleanup(kind: .openai, apiKey: key, models: config.cleanup.models,
                                 prompt: config.cleanup.prompt)
        case .anthropic:
            guard let key = env["ANTHROPIC_API_KEY"], !key.isEmpty else {
                throw CleanupError.missingAPIKey("ANTHROPIC_API_KEY")
            }
            return RoutedCleanup(kind: .anthropic, apiKey: key, models: config.cleanup.models,
                                 prompt: config.cleanup.prompt)
        }
    }

    /// The provider a transform runs through.
    ///
    /// Two deliberate differences from cleanup: the transform system prompt (the
    /// cleaner's prompt forbids the rewriting a transform exists to do), and no
    /// `<transcript>` wrapping, because the runner delimits instruction and text
    /// itself. Always the stronger local model regardless of script — rewriting is
    /// harder than cleaning, and the 1.5b is visibly weaker at it. `nil` when
    /// cleanup is off: there is no model to ask.
    public static func makeTransformer(config: Config, env: DotEnv) throws
        -> (any CleanupProvider)? {
        let model = config.cleanup.transformModel.isEmpty
            ? config.cleanup.models.arabic
            : config.cleanup.transformModel
        switch config.cleanup.provider {
        case .off:
            return nil
        case .ollama:
            return ChatCleanup(kind: .ollama, apiKey: nil, model: model,
                               prompt: transformSystemPrompt, wrap: { $0 })
        case .openai:
            guard let key = env["OPENAI_API_KEY"], !key.isEmpty else {
                throw CleanupError.missingAPIKey("OPENAI_API_KEY")
            }
            return ChatCleanup(kind: .openai, apiKey: key, model: model,
                               prompt: transformSystemPrompt, wrap: { $0 })
        case .anthropic:
            guard let key = env["ANTHROPIC_API_KEY"], !key.isEmpty else {
                throw CleanupError.missingAPIKey("ANTHROPIC_API_KEY")
            }
            return ChatCleanup(kind: .anthropic, apiKey: key, model: model,
                               prompt: transformSystemPrompt, wrap: { $0 })
        }
    }

    /// The provider a polish pass runs through.
    ///
    /// Like `makeTransformer`, and for the same reason: the cleaner's prompt
    /// forbids exactly the rewriting this stage exists to do, so it cannot be the
    /// same provider with a different argument. Always the stronger local model —
    /// the small one translates Arabic instead of rewriting it. `nil` when cleanup
    /// is off, or when the mode is `clean`: there is nothing to ask.
    public static func makePolisher(config: Config, env: DotEnv) throws
        -> (any CleanupProvider)? {
        guard config.cleanup.mode == .polish else { return nil }
        let kind = config.cleanup.provider
        let key: String?
        switch kind {
        case .off:
            return nil
        case .ollama:
            key = nil
        case .openai:
            guard let k = env["OPENAI_API_KEY"], !k.isEmpty else {
                throw CleanupError.missingAPIKey("OPENAI_API_KEY")
            }
            key = k
        case .anthropic:
            guard let k = env["ANTHROPIC_API_KEY"], !k.isEmpty else {
                throw CleanupError.missingAPIKey("ANTHROPIC_API_KEY")
            }
            key = k
        }
        func provider(_ model: String) -> any CleanupProvider {
            ChatCleanup(kind: kind, apiKey: key, model: model,
                        prompt: polishSystemPrompt, wrap: wrapTranscript)
        }
        // A pinned model is a decision someone made; use it for everything.
        if !config.cleanup.polishModel.isEmpty {
            return provider(config.cleanup.polishModel)
        }
        // Polish goes to the bigger model whatever the language.
        //
        // The small one was chosen here on a benchmark of short cases, and it does
        // not survive contact with a real dictation. Measured on one transcript at
        // four lengths, share of the spoken words still present afterwards:
        //
        //             20 words   40 words   60 words   101 words
        //   1.5b          35%        35%       103%         56%
        //   3b            95%        98%        98%         99%
        //
        // At 101 words — half a minute of speaking — the small model returned
        // "The meeting is on Tuesday at four o'clock", which is a worked example
        // out of its own prompt and nothing the speaker said. Rewriting is the
        // stage with licence to delete, so it is the stage that must be trusted,
        // and a model that is erratic cannot be. Cleanup still routes by script:
        // that job is smaller, and the small model is good at it.
        let models = config.cleanup.models
        return provider(models.arabic)
    }

    /// Default model per script for a provider, used by first-run detection.
    ///
    /// The local pair is the benchmarked outcome: 1.5b is faithful and fast on
    /// English but translates Arabic; 3b holds Arabic and mixed speech correctly.
    /// Hosted providers are strong enough at both that one model serves each.
    public static func defaultModels(for kind: CleanupKind) -> CleanupModels {
        switch kind {
        case .openai:
            CleanupModels(latin: "gpt-4o-mini", arabic: "gpt-4o-mini")
        case .anthropic:
            CleanupModels(latin: "claude-haiku-4-5-20251001",
                          arabic: "claude-haiku-4-5-20251001")
        case .ollama:
            CleanupModels(latin: "qwen2.5:1.5b", arabic: "qwen2.5:3b")
        case .off:
            CleanupModels(latin: "", arabic: "")
        }
    }
}
