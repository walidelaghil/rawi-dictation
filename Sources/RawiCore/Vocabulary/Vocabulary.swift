import Foundation

public struct DictionaryTerm: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var term: String
    public var note: String
    /// Suggested by Rawi and accepted, rather than typed in. Marked so it can be
    /// removed without wondering where it came from.
    public var addedAutomatically: Bool

    public init(id: UUID = UUID(), term: String, note: String = "",
                addedAutomatically: Bool = false) {
        self.id = id
        self.term = term
        self.note = note
        self.addedAutomatically = addedAutomatically
    }
}

public struct Snippet: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var trigger: String
    public var expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

/// What a dictation needs to know about your vocabulary, captured at key-press.
public struct VocabularySnapshot: Sendable, Equatable {
    public let whisperPrompt: String
    public let glossary: String
    /// The exact spellings, for the deterministic corrector.
    public let terms: [String]
    public let snippets: [Snippet]

    public init(whisperPrompt: String, glossary: String,
                terms: [String] = [], snippets: [Snippet]) {
        self.whisperPrompt = whisperPrompt
        self.glossary = glossary
        self.terms = terms
        self.snippets = snippets
    }

    public static let empty = VocabularySnapshot(whisperPrompt: "", glossary: "",
                                                 terms: [], snippets: [])
}

public final class VocabularyStore: @unchecked Sendable {
    private struct Payload: Codable {
        var terms: [DictionaryTerm]
        var snippets: [Snippet]
    }

    private let url: URL
    private let lock = NSLock()
    private var payload = Payload(terms: [], snippets: [])

    public static var defaultURL: URL {
        Config.supportDirectory.appendingPathComponent("vocabulary.json")
    }

    public init(url: URL = VocabularyStore.defaultURL) {
        self.url = url
        load()
    }

    public var terms: [DictionaryTerm] { lock.withLock { payload.terms } }
    public var snippets: [Snippet] { lock.withLock { payload.snippets } }

    @discardableResult
    public func addTerm(_ term: String, note: String = "", automatic: Bool = false) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return lock.withLock {
            // Case-insensitive: "Salla" and "salla" are the same term, and having
            // both would waste the whisper prompt's limited budget.
            guard !payload.terms.contains(where: {
                $0.term.compare(trimmed, options: .caseInsensitive) == .orderedSame
            }) else { return false }
            payload.terms.append(DictionaryTerm(term: trimmed, note: note,
                                                addedAutomatically: automatic))
            save()
            return true
        }
    }

    public func removeTerm(_ id: UUID) {
        lock.withLock { payload.terms.removeAll { $0.id == id }; save() }
    }

    @discardableResult
    public func addSnippet(trigger: String, expansion: String) -> Bool {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !e.isEmpty else { return false }
        return lock.withLock {
            guard !payload.snippets.contains(where: {
                $0.trigger.compare(t, options: .caseInsensitive) == .orderedSame
            }) else { return false }
            payload.snippets.append(Snippet(trigger: t, expansion: e))
            save()
            return true
        }
    }

    public func removeSnippet(_ id: UUID) {
        lock.withLock { payload.snippets.removeAll { $0.id == id }; save() }
    }

    public func snapshot() -> VocabularySnapshot {
        VocabularySnapshot(whisperPrompt: whisperPrompt(),
                           glossary: glossaryClause(),
                           terms: terms.map(\.term),
                           snippets: snippets)
    }

    /// Comma-joined terms for the decoder hint (`whisper-cli --prompt`, and the
    /// `prompt` field on the hosted APIs, which document exactly this format).
    ///
    /// **Best effort, not the mechanism.** Measured on `large-v3-turbo`: a comma
    /// list does not reliably shift the decoder — only one hand-written phrasing
    /// did, and every list-shaped sentence failed. It worked well on `small.en`,
    /// which is not the model shipped. The cleanup glossary is what actually
    /// enforces spelling; this costs nothing and occasionally helps.
    ///
    /// Capped deliberately: the flag takes at most `n_text_ctx/2` tokens and
    /// overflowing it degrades transcription rather than erroring — a silent
    /// regression that looks like the model getting worse. Terms are never
    /// truncated mid-word, because half a term is a wrong hint.
    public func whisperPrompt(maxCharacters: Int = 400) -> String {
        var out: [String] = []
        var length = 0
        for term in terms.map(\.term) {
            let addition = out.isEmpty ? term.count : term.count + 2
            guard length + addition <= maxCharacters else { break }
            out.append(term)
            length += addition
        }
        return out.joined(separator: ", ")
    }

    /// Appended to the cleanup prompt. **This is the layer that works.** The
    /// decoder hint is unreliable on the shipped model, so the glossary is what
    /// actually gets a name spelled correctly.
    public func glossaryClause() -> String {
        let list = terms.map(\.term)
        guard !list.isEmpty else { return "" }
        return "\n\nThese terms may appear; spell them exactly as written here: "
             + list.joined(separator: ", ") + "."
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        payload = decoded
    }

    /// Caller holds the lock.
    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(payload).write(to: url, options: .atomic)
    }
}
