import Foundation

/// Sends the raw transcript to a chat-completion API for filler removal,
/// punctuation, and casing. One implementation covers OpenAI, Anthropic, and a
/// local Ollama, because only the request shape and response path differ.
///
/// Cleanup failure is deliberately non-fatal: `DictationController` catches it and
/// inserts the raw transcript, so a provider outage can never lose your dictation.
public final class ChatCleanup: CleanupProvider, @unchecked Sendable {
    private let kind: CleanupKind
    private let apiKey: String?
    private let model: String
    private let prompt: String
    private let session: URLSession

    private let lock = NSLock()
    private var currentTask: URLSessionDataTask?

    public init(kind: CleanupKind, apiKey: String?, model: String,
                prompt: String, session: URLSession = .shared) {
        self.kind = kind
        self.apiKey = apiKey
        self.model = model
        self.prompt = prompt
        self.session = session
    }

    public func clean(_ transcript: String) async throws -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return transcript }

        var request = URLRequest(url: Self.endpoint(kind: kind))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout(for: kind)

        switch kind {
        case .openai:
            request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey ?? "", forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .ollama, .off:
            break
        }
        request.httpBody = try Self.requestBody(kind: kind, model: model,
                                                prompt: prompt, transcript: trimmed)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    self.lock.withLock { self.currentTask = nil }

                    if let error = error as? URLError, error.code == .cancelled {
                        continuation.resume(throwing: CleanupError.cancelled); return
                    }
                    if let error {
                        continuation.resume(throwing: CleanupError.badResponse(
                            error.localizedDescription)); return
                    }
                    guard let data else {
                        continuation.resume(throwing: CleanupError.badResponse("no data")); return
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        continuation.resume(throwing: CleanupError.badResponse("HTTP \(status)"))
                        return
                    }
                    do {
                        let text = try Self.parse(kind: self.kind, data)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: text.isEmpty ? trimmed : text)
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

    /// A hosted API that has not answered in 20s is not going to. A *local* model
    /// can legitimately take that long on a cold start — Ollama loads weights from
    /// disk on the first call after an idle period, and routing two models by
    /// script makes a cold start more likely, not less. Timing that out would lose
    /// the cleanup on the first dictation of the day.
    static func timeout(for kind: CleanupKind) -> TimeInterval {
        switch kind {
        case .ollama: 90
        case .openai, .anthropic, .off: 20
        }
    }

    // MARK: - Wire format

    static func endpoint(kind: CleanupKind) -> URL {
        switch kind {
        case .openai: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        case .ollama: URL(string: "http://localhost:11434/api/chat")!
        case .off: preconditionFailure("`off` has no endpoint; use NoopCleanup")
        }
    }

    static func requestBody(kind: CleanupKind, model: String,
                            prompt: String, transcript: String) throws -> Data {
        // Delimited so the model can distinguish dictated content from instructions.
        let user = wrapTranscript(transcript)
        let payload: [String: Any]
        switch kind {
        case .openai:
            payload = [
                "model": model,
                "temperature": 0,
                "messages": [
                    ["role": "system", "content": prompt],
                    ["role": "user", "content": user],
                ],
            ]
        case .anthropic:
            // Anthropic takes the instruction as a top-level `system` field,
            // not as a system-role message.
            payload = [
                "model": model,
                "max_tokens": 2048,
                "temperature": 0,
                "system": prompt,
                "messages": [["role": "user", "content": user]],
            ]
        case .ollama:
            // `keep_alive` holds the model in memory between dictations. Ollama's
            // default unloads after 5 minutes idle, which would make the first
            // dictation after a quiet spell pay a multi-second reload.
            payload = [
                "model": model,
                "stream": false,
                "keep_alive": "30m",
                "options": ["temperature": 0],
                "messages": [
                    ["role": "system", "content": prompt],
                    ["role": "user", "content": user],
                ],
            ]
        case .off:
            preconditionFailure("`off` builds no request; use NoopCleanup")
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func parse(kind: CleanupKind, _ data: Data) throws -> String {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch kind {
        case .openai:
            guard let choices = root?["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw CleanupError.badResponse("no choices[0].message.content")
            }
            return content
        case .anthropic:
            guard let content = root?["content"] as? [[String: Any]],
                  let text = content.first(where: { $0["type"] as? String == "text" })?["text"]
                      as? String else {
                throw CleanupError.badResponse("no content[].text")
            }
            return text
        case .ollama:
            guard let message = root?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw CleanupError.badResponse("no message.content")
            }
            return content
        case .off:
            throw CleanupError.badResponse("`off` parses nothing")
        }
    }
}
