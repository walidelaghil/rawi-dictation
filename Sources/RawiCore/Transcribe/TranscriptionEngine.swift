import Foundation

public protocol TranscriptionEngine: AnyObject, Sendable {
    func transcribe(wav: URL) async throws -> String
    func cancel()
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
    public static func make(config: Config, env: DotEnv) throws -> any TranscriptionEngine {
        switch config.engine {
        case .whispercpp:
            return WhisperCppEngine(binary: config.whispercpp.binary,
                                    model: Config.expand(config.whispercpp.model),
                                    language: config.whispercpp.language,
                                    threads: config.whispercpp.threads)
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
