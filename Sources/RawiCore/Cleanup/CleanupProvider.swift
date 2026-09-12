import Foundation

public protocol CleanupProvider: AnyObject, Sendable {
    /// `instruction` shapes this one dictation for where it is going. It is a
    /// per-call argument rather than provider state because the destination
    /// changes with every key-press while the provider is built once.
    func clean(_ transcript: String, instruction: String) async throws -> String
    func cancel()
}

public extension CleanupProvider {
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
        let model = config.cleanup.models.arabic
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
