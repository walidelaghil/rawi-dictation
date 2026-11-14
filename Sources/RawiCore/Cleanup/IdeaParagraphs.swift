import Foundation

/// Breaks a long dictation into one paragraph per idea.
///
/// `SpokenParagraphs` only breaks where the speaker *says* the subject is
/// changing ("by the way", "separately"), and most people never do: a minute of
/// speech came out as one block. Wispr Flow breaks it the way a writer would.
///
/// Pauses were tried first and do not work. Whisper's segment timestamps run
/// back to back across real pauses (0.00 s gaps either side of a two-second
/// silence on a test clip), so they cannot say where an idea ended.
///
/// So a model reads the sentences, but it is never allowed to write them. It is
/// shown numbered sentences and answers with numbers only — which sentences open
/// a paragraph — and the break is made here, in code. The words that reach the
/// page are exactly the words that came out of transcription. Small local models
/// asked to *rewrite* with paragraphs deleted the very words that marked the
/// change; a model that can only return numbers has nothing to delete.
public protocol ParagraphPlanner: Sendable {
    /// One-based numbers of the sentences that begin a new paragraph.
    func paragraphStarts(_ sentences: [String]) async throws -> [Int]
}

public enum IdeaParagraphs {
    /// Below this there is rarely more than one idea, and the call is not free.
    static let minSentences = 4
    static let minWords = 45
    /// The model answers in 0.2–0.6 s. Past this the dictation is delivered as it
    /// would have been anyway: a slow call must never be what you wait for.
    public static let deadline: Duration = .milliseconds(1500)

    public static func worthPlanning(_ text: String) -> Bool {
        // Text that already has line breaks (a snippet, a list) has a shape.
        guard !text.contains("\n") else { return false }
        guard text.split(whereSeparator: \.isWhitespace).count >= minWords else { return false }
        return SpokenParagraphs.sentencesOf(text).count >= minSentences
    }

    /// The paragraphs, or nil when there is nothing to do or the plan is unusable.
    public static func plan(_ text: String, using planner: any ParagraphPlanner,
                            deadline: Duration = IdeaParagraphs.deadline) async throws -> [String]? {
        guard worthPlanning(text) else { return nil }
        let sentences = SpokenParagraphs.sentencesOf(text)
        let starts = try await withThrowingTaskGroup(of: [Int]?.self) { group in
            group.addTask { try await planner.paragraphStarts(sentences) }
            group.addTask {
                try await Task.sleep(for: deadline)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
        guard let starts else { throw PlanError.timedOut }
        let paragraphs = apply(starts: starts, to: sentences)
        return paragraphs.count > 1 ? paragraphs : nil
    }

    /// Only well-formed numbers count: in range, never the first sentence. A model
    /// that answers nonsense gets no breaks, not wrong ones.
    static func apply(starts: [Int], to sentences: [String]) -> [String] {
        let breaks = Set(starts.filter { $0 >= 2 && $0 <= sentences.count })
        var paragraphs: [[String]] = [[]]
        for (index, sentence) in sentences.enumerated() {
            if breaks.contains(index + 1), !paragraphs[paragraphs.count - 1].isEmpty {
                paragraphs.append([])
            }
            paragraphs[paragraphs.count - 1].append(sentence)
        }
        return paragraphs.map { $0.joined(separator: " ") }
    }

    public enum PlanError: Error, LocalizedError {
        case timedOut
        case badResponse(String)
        public var errorDescription: String? {
            switch self {
            case .timedOut: "no answer in time"
            case .badResponse(let why): why
            }
        }
    }
}

/// Asks a Groq chat model for the plan. Only used when transcription already goes
/// to Groq, so no text leaves the Mac that was not already leaving it as audio.
public final class GroqParagraphPlanner: ParagraphPlanner, @unchecked Sendable {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    /// Measured on dictations in English and Arabic: the same breaks on every run,
    /// in 0.2–0.6 s. gpt-oss-20b gave the same breaks but took up to 0.9 s, and
    /// gpt-oss-120b left out the opening line's break.
    public static let defaultModel = "qwen/qwen3.8-27b"

    static let system = """
        You add paragraph breaks to dictated text, the way a careful writer would: \
        one paragraph per idea. You receive numbered sentences. Reply with JSON only: \
        {"starts": [n, ...]}, the numbers of the sentences that begin a new paragraph. \
        Never include 1. Begin a new paragraph when the speaker moves on to a \
        different point, topic, request, or item. Keep together the sentences that \
        explain, justify, or add detail to the same point; a point and its reasons \
        are one paragraph. A one-sentence paragraph is right for a short opening \
        line, a sign-off, or a point that stands alone, not for every sentence. If \
        the text is one idea, reply {"starts": []}. The text may be in any \
        language, including Arabic.
        """

    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String = GroqParagraphPlanner.defaultModel,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func paragraphStarts(_ sentences: [String]) async throws -> [Int] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.requestBody(model: model, sentences: sentences)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw IdeaParagraphs.PlanError.badResponse("HTTP \(status)")
        }
        return try Self.parse(data)
    }

    static func numbered(_ sentences: [String]) -> String {
        sentences.enumerated().map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    static func requestBody(model: String, sentences: [String]) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": numbered(sentences)],
            ],
        ]
        // Qwen 3 thinks out loud by default, which costs time and buys nothing for
        // a question this small.
        if model.hasPrefix("qwen/") { body["reasoning_effort"] = "none" }
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func parse(_ data: Data) throws -> [Int] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let plan = try JSONSerialization.jsonObject(with: Data(content.utf8))
                  as? [String: Any],
              let starts = plan["starts"] as? [Any]
        else { throw IdeaParagraphs.PlanError.badResponse("no starts in the answer") }
        return starts.compactMap { ($0 as? NSNumber)?.intValue }
    }
}
