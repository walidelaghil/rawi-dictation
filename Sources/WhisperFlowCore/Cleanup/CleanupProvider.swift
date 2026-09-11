import Foundation

public protocol CleanupProvider: AnyObject, Sendable {
    func clean(_ transcript: String) async throws -> String
    func cancel()
}

public enum CleanupError: Error, LocalizedError, Equatable {
    case missingAPIKey(String)
    case badResponse(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let k): "Missing \(k) in ~/.config/whisperflow/.env"
        case .badResponse(let m): "Cleanup provider returned an unexpected response: \(m)"
        case .cancelled: "Cancelled"
        }
    }
}

/// Used when `cleanup.provider` is `off`. Returns the transcript untouched.
public final class NoopCleanup: CleanupProvider {
    public init() {}
    public func clean(_ transcript: String) async throws -> String { transcript }
    public func cancel() {}
}

public enum CleanupProviderFactory {
    public static func make(config: Config, env: DotEnv) throws -> any CleanupProvider {
        switch config.cleanup.provider {
        case .off:
            return NoopCleanup()
        case .ollama:
            return ChatCleanup(kind: .ollama, apiKey: nil,
                               model: config.cleanup.model, prompt: config.cleanup.prompt)
        case .openai:
            guard let key = env["OPENAI_API_KEY"], !key.isEmpty else {
                throw CleanupError.missingAPIKey("OPENAI_API_KEY")
            }
            return ChatCleanup(kind: .openai, apiKey: key,
                               model: config.cleanup.model, prompt: config.cleanup.prompt)
        case .anthropic:
            guard let key = env["ANTHROPIC_API_KEY"], !key.isEmpty else {
                throw CleanupError.missingAPIKey("ANTHROPIC_API_KEY")
            }
            return ChatCleanup(kind: .anthropic, apiKey: key,
                               model: config.cleanup.model, prompt: config.cleanup.prompt)
        }
    }

    /// A sensible default model per provider, used by first-run detection.
    public static func defaultModel(for kind: CleanupKind) -> String {
        switch kind {
        case .openai: "gpt-4o-mini"
        case .anthropic: "claude-haiku-4-5-20251001"
        // 1.5b rather than 3b deliberately: benchmarked on real whisper output,
        // the 3b is "smart" enough to rewrite and summarise the dictation, which is
        // precisely what the cleanup prompt forbids. The 1.5b stays faithful and is
        // also ~40% faster.
        case .ollama: "qwen2.5:1.5b"
        case .off: ""
        }
    }
}
