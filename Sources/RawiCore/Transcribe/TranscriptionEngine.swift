import Foundation

public protocol TranscriptionEngine: AnyObject, Sendable {
    /// `prompt` biases decoding toward words it would otherwise get wrong —
    /// names, jargon, product names. Both whisper.cpp and the hosted APIs accept
    /// one, so it belongs in the protocol rather than in one implementation.
    func transcribe(wav: URL, prompt: String) async throws -> String
    func cancel()
    /// Transcribe as this language from now on, rather than detecting it.
    func use(language: DictationLanguage)
}

public extension TranscriptionEngine {
    func transcribe(wav: URL) async throws -> String { try await transcribe(wav: wav, prompt: "") }
    /// An engine that is always told its language by configuration has nothing to
    /// do here, and should not have to say so.
    func use(language: DictationLanguage) {}
}

public enum TranscriptionError: Error, LocalizedError, Equatable {
    case binaryNotFound(String)
    case modelNotFound(String)
    case processFailed(exitCode: Int32, stderrTail: String)
    /// The resident transcription server refused the request.
    case serverRejected(status: Int, detail: String)
    case cancelled
    case emptyResult
    case apiError(status: Int, message: String)
    case missingAPIKey(String)

    public var errorDescription: String? {
        switch self {
        // Plain words: this reaches the pill, where a file path helps nobody.
        case .binaryNotFound: "whisper.cpp is not installed"
        case .modelNotFound: "The speech model is not downloaded"
        case .processFailed(let code, let tail): "whisper-cli exited \(code): \(tail)"
        case .serverRejected(let status, let detail):
            status == 400
                // The one the user can act on, and the only 400 this server sends.
                ? "The recording could not be read"
                : "Transcription server error \(status): \(detail)"
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
            // The resident model detects for nothing, so it is not asked twice.
            //
            // The separate detector was measured against `auto` on a loaded Mac
            // running the q5_0 model, where asking the big model to work the
            // language out cost a second encoder pass: 6.8s against 3.4s. On
            // q8_0 that pass is free — measured on the same clip, told 56ms,
            // detecting itself 47ms — while the detector is a second HTTP call
            // that transcribes the whole recording with the base model before the
            // real one starts. On a nine-word dictation that was 300ms of the
            // 340ms spent transcribing, to save nothing.
            //
            // The command line still uses it: there each pass is a process launch
            // and a model load, so the original measurement still holds there.
            let detectModel = Config.expand(settings.detectModel)
            let detector = settings.language == "auto"
                && !settings.useServer
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
