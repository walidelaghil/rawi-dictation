import Foundation

public protocol TranscriptionEngine: AnyObject, Sendable {
    /// `prompt` biases decoding toward words it would otherwise get wrong —
    /// names, jargon, product names. Both whisper.cpp and the hosted APIs accept
    /// one, so it belongs in the protocol rather than in one implementation.
    func transcribe(wav: URL, prompt: String) async throws -> String
    func cancel()
}

public extension TranscriptionEngine {
    func transcribe(wav: URL) async throws -> String { try await transcribe(wav: wav, prompt: "") }
}

public enum TranscriptionError: Error, LocalizedError, Equatable {
    case binaryNotFound(String)
    case modelNotFound(String)
    case processFailed(exitCode: Int32, stderrTail: String)
    case cancelled
    case emptyResult
    case apiError(status: Int, message: String)
    case missingAPIKey(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let b): "whisper-cli not found (looked for “\(b)”)"
        case .modelNotFound(let m): "Whisper model not found at \(m)"
        case .processFailed(let code, let tail): "whisper-cli exited \(code): \(tail)"
        case .cancelled: "Cancelled"
        case .emptyResult: "Nothing was transcribed"
        case .apiError(let s, let m): "Transcription API error \(s): \(m)"
        case .missingAPIKey(let k): "Missing \(k) in ~/.config/rawi/.env"
        }
    }
}

/// Builds the engine named by config. API keys come from `.env` only.
public enum TranscriptionEngineFactory {
    public static func make(config: Config, env: DotEnv,
                            log: (any Logging)? = nil) throws -> any TranscriptionEngine {
        switch config.engine {
        case .whispercpp:
            let settings = config.whispercpp
            // The detector only earns its place when the language is not already
            // known: `auto` is what costs a second encoder pass.
            let detectModel = Config.expand(settings.detectModel)
            let detector = settings.language == "auto"
                && FileManager.default.fileExists(atPath: detectModel)
                ? LanguageDetector(serverBinary: settings.serverBinary, model: detectModel,
                                   threads: max(2, settings.threads / 2),
                                   port: settings.serverPort + 1, log: log ?? SilentLog())
                : nil
            if settings.useServer {
                return WhisperServerEngine(
                    binary: settings.serverBinary,
                    model: Config.expand(settings.model),
                    threads: settings.threads,
                    language: settings.language,
                    port: settings.serverPort,
                    detector: detector,
                    log: log ?? SilentLog())
            }
            return WhisperCppEngine(binary: settings.binary,
                                    model: Config.expand(settings.model),
                                    language: settings.language,
                                    threads: settings.threads,
                                    detector: detector)
        case .groq:
            guard let key = env["GROQ_API_KEY"], !key.isEmpty else {
                throw TranscriptionError.missingAPIKey("GROQ_API_KEY")
            }
            return WhisperAPIEngine(provider: .groq, apiKey: key, model: config.api.groqModel)
        case .openai:
            guard let key = env["OPENAI_API_KEY"], !key.isEmpty else {
                throw TranscriptionError.missingAPIKey("OPENAI_API_KEY")
            }
            return WhisperAPIEngine(provider: .openai, apiKey: key, model: config.api.openaiModel)
        }
    }
}
