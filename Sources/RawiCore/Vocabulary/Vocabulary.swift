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
        /// Terms you removed. Without this, anything learned automatically comes
        /// straight back on the next dictation and removing it means nothing.
        var blocked: [String] = []
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
    public var blocked: [String] { lock.withLock { payload.blocked } }
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

    /// Removing a learned term also blocks it: you are telling Rawi it was wrong,
    /// and it must not decide otherwise tomorrow. A term you typed in yourself is
    /// simply removed — there is nothing to argue with.
    public func removeTerm(_ id: UUID) {
        lock.withLock {
            if let term = payload.terms.first(where: { $0.id == id }),
               term.addedAutomatically {
                let lower = term.term.lowercased()
                if !payload.blocked.contains(lower) { payload.blocked.append(lower) }
            }
            payload.terms.removeAll { $0.id == id }
            save()
        }
    }

    /// Brings the learned half of the dictionary in line with the evidence.
    ///
    /// Terms you added by hand are never touched. Learned terms that no longer
    /// meet the bar are dropped rather than left to accumulate: the whisper
    /// prompt has a budget, and a term you stopped saying months ago is spending
    /// it. Returns what changed, for the log.
    @discardableResult
    public func syncLearned(_ learned: [LearnedTerm]) -> (added: [String], dropped: [String]) {
        lock.withLock {
            let wanted = Dictionary(uniqueKeysWithValues:
                learned.map { ($0.term.lowercased(), $0) })
            let manual = Set(payload.terms.filter { !$0.addedAutomatically }
                .map { $0.term.lowercased() })

            let dropped = payload.terms
                .filter { $0.addedAutomatically && wanted[$0.term.lowercased()] == nil }
                .map(\.term)
            payload.terms.removeAll {
                $0.addedAutomatically && wanted[$0.term.lowercased()] == nil
            }

            var added: [String] = []
            for (lower, term) in wanted where !manual.contains(lower) {
                if let index = payload.terms.firstIndex(where: {
                    $0.term.lowercased() == lower
                }) {
                    payload.terms[index].note = term.note        // refresh the evidence
                    payload.terms[index].term = term.term
                } else {
                    payload.terms.append(DictionaryTerm(term: term.term, note: term.note,
                                                        addedAutomatically: true))
                    added.append(term.term)
                }
            }
            if !added.isEmpty || !dropped.isEmpty { save() }
            return (added, dropped)
        }
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
