import Foundation

/// Hosted Whisper transcription. Groq and OpenAI expose the same multipart
/// endpoint shape, so one implementation covers both.
///
/// The API key is held only in memory and is never logged or included in an error.
public final class WhisperAPIEngine: TranscriptionEngine, @unchecked Sendable {
    private let provider: EngineKind
    private let apiKey: String
    private let model: String
    private let session: URLSession

    private let lock = NSLock()
    private var currentTask: URLSessionUploadTask?

    public init(provider: EngineKind, apiKey: String, model: String,
                session: URLSession = .shared) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(wav: URL) async throws -> String {
        let wavData = try Data(contentsOf: wav)
        let boundary = "WhisperFlow-\(UUID().uuidString)"

        var request = URLRequest(url: Self.endpoint(for: provider))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        let body = Self.multipartBody(boundary: boundary, model: model,
                                      filename: wav.lastPathComponent, wav: wavData)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, from: body) { data, response, error in
                    self.lock.withLock { self.currentTask = nil }

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
                        let text = WhisperCppEngine.cleanTranscript(try Self.parseResponse(data))
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
                              filename: String, wav: Data) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "json")

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
