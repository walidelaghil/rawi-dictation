import Foundation

/// Hosted Whisper transcription. Groq and OpenAI expose the same multipart
/// endpoint shape, so one implementation covers both.
///
/// The API key is held only in memory and is never logged or included in an error.
public final class WhisperAPIEngine: TranscriptionEngine, @unchecked Sendable {
    private let provider: EngineKind
    private let apiKey: String
    private let model: String
    /// The model used for speech that may mix languages. See `plan`.
    private let mixedModel: String?
    private let session: URLSession

    private let requestedLanguage: String
    /// How long one request may take before the caller is better served elsewhere.
    private let timeout: TimeInterval

    private let lock = NSLock()
    private var currentTask: URLSessionUploadTask?
    private var chosenLanguage: DictationLanguage = .auto
    private var lastConnected: ContinuousClock.Instant?

    public init(provider: EngineKind, apiKey: String, model: String,
                language: String = "auto", timeout: TimeInterval = 20,
                mixedModel: String? = nil,
                session: URLSession = .shared) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.mixedModel = mixedModel
        self.requestedLanguage = language
        self.timeout = timeout
        self.session = session
    }

    public func use(language: DictationLanguage) {
        lock.withLock { chosenLanguage = language }
    }

    /// The language to send, or nil to let the provider detect it. Detection
    /// there is part of the one request, not a second pass as it is locally.
    var language: String? {
        let code = lock.withLock { chosenLanguage.whisperCode } ?? requestedLanguage
        return code == "auto" || code.isEmpty ? nil : code
    }

    /// Opens the connection while the user is still speaking. DNS, TCP and TLS to
    /// the provider cost 100 to 300 ms that would otherwise land after release.
    /// The pooled connection in `session` is what the real request then reuses.
    public func prefetch() {
        let now = ContinuousClock.now
        let stale = lock.withLock { () -> Bool in
            defer { lastConnected = now }
            guard let last = lastConnected else { return true }
            return last.duration(to: now) > .seconds(20)
        }
        guard stale else { return }
        var request = URLRequest(url: Self.endpoint(for: provider))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        session.dataTask(with: request) { _, _, _ in }.resume()
    }

    /// Primes the decoder with text that switches language mid-sentence, which is
    /// what makes it keep both. Without it Whisper picks one language for the
    /// whole recording and translates or drops the other.
    /// One short mixed sentence and no full stop. A longer, finished passage made
    /// whisper-large-v3 say a short clip twice ("Testing the recording." twice)
    /// on real recordings; this one did not, and kept both languages as well.
    static let mixedPrimer = "يعني we need to talk about the project بكرة"
    /// Under this the primer does harm: "تمام" came back as "دمامام".
    static let mixedMinSeconds = 2.0

    struct Plan: Equatable { let model: String; let prompt: String }

    /// Which model and prompt to send. Only when the language is left to the
    /// provider and there is enough speech for the primer not to dominate it.
    static func plan(model: String, mixedModel: String?, language: String?,
                     seconds: Double, dictionary: String) -> Plan {
        guard language == nil, let mixedModel, !mixedModel.isEmpty,
              seconds >= mixedMinSeconds else {
            return Plan(model: model, prompt: dictionary)
        }
        return Plan(model: mixedModel,
                    prompt: dictionary.isEmpty ? mixedPrimer : mixedPrimer + " " + dictionary)
    }

    public func transcribe(wav: URL, prompt: String = "") async throws -> String {
        let wavData = try Data(contentsOf: wav)
        let plan = Self.plan(model: model, mixedModel: provider == .groq ? mixedModel : nil,
                             language: language, seconds: AudioFile.seconds(bytes: wavData.count),
                             dictionary: prompt)
        let boundary = "Rawi-\(UUID().uuidString)"

        var request = URLRequest(url: Self.endpoint(for: provider))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        let body = Self.multipartBody(boundary: boundary, model: plan.model,
                                      filename: wav.lastPathComponent, wav: wavData,
                                      prompt: plan.prompt, language: language)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, from: body) { data, response, error in
                    self.lock.withLock {
                        self.currentTask = nil
                        self.lastConnected = .now
                    }

                    if let error = error as? URLError, error.code == .cancelled {
                        continuation.resume(throwing: TranscriptionError.cancelled); return
                    }
                    if let error {
                        continuation.resume(throwing: TranscriptionError.apiError(
                            status: 0, message: error.localizedDescription)); return
                    }
                    guard let data else {
                        continuation.resume(throwing: TranscriptionError.emptyResult); return
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        let message = (try? Self.errorMessage(data)) ?? "HTTP \(status)"
                        continuation.resume(throwing: TranscriptionError.apiError(
                            status: status, message: message)); return
                    }
                    do {
                        let text = RepeatedTranscript.collapse(
                            WhisperCppEngine.cleanTranscript(try Self.parseResponse(data)))
                        guard !text.isEmpty else {
                            continuation.resume(throwing: TranscriptionError.emptyResult); return
                        }
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                lock.withLock { currentTask = task }
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    public func cancel() {
        lock.withLock {
            currentTask?.cancel()
            currentTask = nil
        }
    }

    // MARK: - Wire format

    static func endpoint(for provider: EngineKind) -> URL {
        switch provider {
        case .groq:
            URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        case .openai:
            URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        case .whispercpp:
            preconditionFailure("whispercpp is a local engine and has no endpoint")
        }
    }

    static func multipartBody(boundary: String, model: String,
                              filename: String, wav: Data, prompt: String = "",
                              language: String? = nil) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "json")
        field("temperature", "0")
        if let language { field("language", language) }
        // Both Groq and OpenAI accept a biasing prompt on this endpoint.
        if !prompt.isEmpty { field("prompt", prompt) }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    static func parseResponse(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let text = object?["text"] as? String { return text }
        throw TranscriptionError.apiError(status: 0,
                                         message: (try? errorMessage(data)) ?? "unexpected response")
    }

    static func errorMessage(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = object?["error"] as? [String: Any],
           let message = error["message"] as? String { return message }
        if let message = object?["message"] as? String { return message }
        throw TranscriptionError.emptyResult
    }
}
