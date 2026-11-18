import Foundation

public struct DictionaryTerm: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var term: String
    public var note: String
    /// Suggested by Rawi and accepted, rather than typed in. Marked so it can be
    /// removed without wondering where it came from.
    public var addedAutomatically: Bool
    /// Learned because you fixed Rawi's spelling of it in a document. The strongest
    /// evidence there is, so the spelling-based learner never drops one.
    public var learnedFromCorrection: Bool
    /// What whisper wrote before you corrected it. Used to put the right spelling
    /// in directly next time, where the two are too far apart to be a near miss.
    public var heardAs: [String]

    public init(id: UUID = UUID(), term: String, note: String = "",
                addedAutomatically: Bool = false, learnedFromCorrection: Bool = false,
                heardAs: [String] = []) {
        self.id = id
        self.term = term
        self.note = note
        self.addedAutomatically = addedAutomatically
        self.learnedFromCorrection = learnedFromCorrection
        self.heardAs = heardAs
    }

    private enum CodingKeys: String, CodingKey {
        case id, term, note, addedAutomatically, learnedFromCorrection, heardAs
    }

    /// Tolerant on purpose. The synthesised decoder fails on a missing key, and
    /// one failing term fails the whole file — snippets included — so a field
    /// added in a newer build would have silently emptied an older dictionary.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        term = try c.decode(String.self, forKey: .term)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        addedAutomatically = try c.decodeIfPresent(Bool.self, forKey: .addedAutomatically) ?? false
        learnedFromCorrection = try c.decodeIfPresent(Bool.self, forKey: .learnedFromCorrection) ?? false
        heardAs = try c.decodeIfPresent([String].self, forKey: .heardAs) ?? []
    }
}

public struct Snippet: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var trigger: String
    public var expansion: String
    /// Hidden in the list (a password, a card number). It still expands when spoken.
    public var sensitive: Bool

    public init(id: UUID = UUID(), trigger: String, expansion: String, sensitive: Bool = false) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.sensitive = sensitive
    }

    private enum CodingKeys: String, CodingKey { case id, trigger, expansion, sensitive }

    /// Tolerant: files written before `sensitive` existed still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try c.decode(String.self, forKey: .trigger)
        expansion = try c.decode(String.self, forKey: .expansion)
        sensitive = try c.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
    }
}

/// What a dictation needs to know about your vocabulary, captured at key-press.
public struct VocabularySnapshot: Sendable, Equatable {
    public let whisperPrompt: String
    public let glossary: String
    /// The exact spellings, for the deterministic corrector.
    public let terms: [String]
    public let snippets: [Snippet]
    /// Misheard spelling → the one you corrected it to.
    public let aliases: [String: String]

    public init(whisperPrompt: String, glossary: String,
                terms: [String] = [], snippets: [Snippet], aliases: [String: String] = [:]) {
        self.whisperPrompt = whisperPrompt
        self.glossary = glossary
        self.terms = terms
        self.snippets = snippets
        self.aliases = aliases
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

        init(terms: [DictionaryTerm], snippets: [Snippet], blocked: [String] = []) {
            self.terms = terms
            self.snippets = snippets
            self.blocked = blocked
        }

        /// A missing list is an empty list, not a reason to discard the others.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            terms = try c.decodeIfPresent([DictionaryTerm].self, forKey: .terms) ?? []
            snippets = try c.decodeIfPresent([Snippet].self, forKey: .snippets) ?? []
            blocked = try c.decodeIfPresent([String].self, forKey: .blocked) ?? []
        }
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

    /// Re-reads the file, for a change made while Rawi was running.
    public func reloadFromDisk() { lock.withLock { load() } }

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

            // Only its own terms: a correction you made is not evidence this learner
            // can overrule by not seeing the word again.
            let isMine = { (t: DictionaryTerm) in t.addedAutomatically && !t.learnedFromCorrection }
            let dropped = payload.terms
                .filter { isMine($0) && wanted[$0.term.lowercased()] == nil }
                .map(\.term)
            payload.terms.removeAll {
                isMine($0) && wanted[$0.term.lowercased()] == nil
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

    /// You changed Rawi's `heard` into `fixed` in a document. Returns true when
    /// `fixed` is new to the dictionary.
    @discardableResult
    public func learnCorrection(heard: String, fixed: String, app: String?,
                                alias: Bool = true) -> Bool {
        let fixedTrimmed = fixed.trimmingCharacters(in: .whitespacesAndNewlines)
        let heardLower = heard.lowercased()
        guard !fixedTrimmed.isEmpty else { return false }
        return lock.withLock {
            // You removed it once; one more correction does not overrule that.
            guard !payload.blocked.contains(fixedTrimmed.lowercased()) else { return false }
            if let index = payload.terms.firstIndex(where: {
                $0.term.compare(fixedTrimmed, options: .caseInsensitive) == .orderedSame
            }) {
                if alias, heardLower != fixedTrimmed.lowercased(),
                   !payload.terms[index].heardAs.contains(heardLower) {
                    payload.terms[index].heardAs.append(heardLower)
                    save()
                }
                return false
            }
            let place = app.map { " in \($0)" } ?? ""
            payload.terms.append(DictionaryTerm(
                term: fixedTrimmed,
                note: "you corrected “\(heard)”\(place)",
                addedAutomatically: true, learnedFromCorrection: true,
                heardAs: alias && heardLower != fixedTrimmed.lowercased() ? [heardLower] : []))
            save()
            return true
        }
    }

    @discardableResult
    public func addSnippet(trigger: String, expansion: String, sensitive: Bool = false) -> Bool {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !e.isEmpty else { return false }
        return lock.withLock {
            guard !payload.snippets.contains(where: {
                $0.trigger.compare(t, options: .caseInsensitive) == .orderedSame
            }) else { return false }
            payload.snippets.append(Snippet(trigger: t, expansion: e, sensitive: sensitive))
            save()
            return true
        }
    }

    public func removeSnippet(_ id: UUID) {
        lock.withLock { payload.snippets.removeAll { $0.id == id }; save() }
    }

    /// Edits a snippet in place. False when empty, or when another snippet already
    /// has that trigger.
    @discardableResult
    public func updateSnippet(_ id: UUID, trigger: String, expansion: String,
                              sensitive: Bool) -> Bool {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !e.isEmpty else { return false }
        return lock.withLock {
            guard let index = payload.snippets.firstIndex(where: { $0.id == id }),
                  !payload.snippets.contains(where: {
                      $0.id != id && $0.trigger.compare(t, options: .caseInsensitive) == .orderedSame
                  }) else { return false }
            payload.snippets[index].trigger = t
            payload.snippets[index].expansion = e
            payload.snippets[index].sensitive = sensitive
            save()
            return true
        }
    }

    /// Puts a removed snippet back where it was. This is what Undo calls.
    public func restoreSnippet(_ snippet: Snippet, at index: Int) {
        lock.withLock {
            guard !payload.snippets.contains(where: { $0.id == snippet.id }) else { return }
            payload.snippets.insert(snippet, at: min(max(index, 0), payload.snippets.count))
            save()
        }
    }

    /// Puts a removed term back, and un-blocks it if removing it had blocked it.
    public func restoreTerm(_ term: DictionaryTerm, at index: Int) {
        lock.withLock {
            guard !payload.terms.contains(where: { $0.id == term.id }) else { return }
            payload.blocked.removeAll { $0 == term.term.lowercased() }
            payload.terms.insert(term, at: min(max(index, 0), payload.terms.count))
            save()
        }
    }

    public func snapshot() -> VocabularySnapshot {
        var aliases: [String: String] = [:]
        for term in terms { for heard in term.heardAs { aliases[heard] = term.term } }
        return VocabularySnapshot(whisperPrompt: whisperPrompt(),
                                  glossary: glossaryClause(),
                                  terms: terms.map(\.term),
                                  snippets: snippets, aliases: aliases)
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
        guard !out.isEmpty else { return "" }
        // A sentence, not a list of words.
        //
        // `--prompt` primes the decoder with text it pretends it just transcribed,
        // so it continues in that register — and a bare comma list has no capital
        // and no full stop. Measured, one dictionary term and a nine-word
        // sentence: "Rawi" as the hint returned "let me check that and get back to
        // you", where no hint returned "Let me check that and get back to you."
        //
        // That lowercase, unpunctuated line then met `CleanupNeeded`, whose rule
        // is that unpunctuated output means whisper had a bad time, so a clean
        // sentence that needed nothing was sent to the rewriter. On this machine
        // that was another three to nine seconds, on every short dictation, caused
        // by the dictionary rather than by anything the speaker said.
        let joined = out.count == 1 ? out[0]
            : out.dropLast().joined(separator: ", ") + " and " + out[out.count - 1]
        return "We use \(joined)."
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
