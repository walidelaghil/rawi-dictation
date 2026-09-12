# Rawi v2 · Phase 4 — Accuracy

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Your names and jargon come out right, and things you say constantly stop needing to be said.

**Architecture:** Dictionary terms are injected twice — into whisper's decoder before it goes wrong, and into the cleanup prompt to catch what slipped through. Snippets expand after cleanup and after the guard, so neither can mangle them. Suggestions come from recurrence in your own history, and corrections are user-initiated, because nothing can observe you editing text without Accessibility.

**Tech Stack:** Swift 6.3, SwiftUI, JSON.

## Global Constraints

- Deployment target **macOS 14.0**; Swift tools **6.0**; strict concurrency.
- **Zero third-party Swift dependencies.**
- Every task ends green: `swift build` and `swift test` both succeed before the commit.
- **No view hardcodes a colour** — everything through `RawiColors`.
- **No permission may be newly required.**
- **Commands is out of scope.** See `docs/BACKLOG.md`.
- Snippet expansion runs **after** `CleanupGuard`, so an expanded URL or address can never be mistaken for the model rewriting your words.
- The whisper initial prompt is capped — `--prompt` takes at most `n_text_ctx/2` tokens, and overflowing it degrades transcription rather than erroring.

## A correction to the approved design

The design canvas says terms are learned automatically after you correct the same
word twice. **That is not buildable on this Mac.** Observing you edit inserted text
requires the Accessibility API, which cannot be granted here.

Two things were investigated before settling:

- `whisper-cli --print-confidence` exists and emits real per-token confidence — but
  as ANSI styling at *subword* granularity, and on a test sentence it underlined
  `W` rather than the actual errors (`Sala`, `Kanji`). It would also corrupt
  transcript parsing, since we read stdout. Not used. Recorded here so it is not
  re-investigated.
- Recurrence in your own history is a genuine signal and is what ships.

So: **suggested, then confirmed by you.** Rawi proposes terms it keeps seeing, and
the History view lets you turn a mangled word into a dictionary entry in one click.
Honest, and it needs nothing this Mac cannot give.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/RawiCore/Vocabulary/DictionaryTerm.swift` | **Create.** A term and its store |
| `Sources/RawiCore/Vocabulary/Snippet.swift` | **Create.** A snippet and its store |
| `Sources/RawiCore/Vocabulary/SnippetExpander.swift` | **Create.** Pure expansion |
| `Sources/RawiCore/Vocabulary/TermSuggester.swift` | **Create.** Candidates from history |
| `Sources/RawiCore/Transcribe/WhisperCppEngine.swift` | **Modify.** Accept an initial prompt |
| `Sources/RawiCore/Cleanup/CleanupProvider.swift` | **Modify.** Glossary into the prompt |
| `Sources/RawiCore/App/DictationController.swift` | **Modify.** Thread vocabulary through |
| `Sources/RawiCore/UI/VocabularyView.swift` | **Create.** Dictionary and Snippets screens |
| `Tests/RawiTests/VocabularyTests.swift` | **Create.** |
| `Tests/RawiTests/SnippetExpanderTests.swift` | **Create.** |
| `Tests/RawiTests/TermSuggesterTests.swift` | **Create.** |

---

## Task 1: Terms and snippets

**Produces:**
```swift
public struct DictionaryTerm: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var term: String           // "Salla"
    public var note: String           // "heard as Sala"
    public var addedAutomatically: Bool
}

public struct Snippet: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var trigger: String        // "my email"
    public var expansion: String
}

public final class VocabularyStore: @unchecked Sendable {
    public init(url: URL = VocabularyStore.defaultURL)
    public static var defaultURL: URL          // …/Application Support/Rawi/vocabulary.json
    public var terms: [DictionaryTerm] { get }
    public var snippets: [Snippet] { get }
    public func addTerm(_ term: String, note: String, automatic: Bool)
    public func removeTerm(_ id: UUID)
    public func addSnippet(trigger: String, expansion: String)
    public func removeSnippet(_ id: UUID)
    /// Comma-joined terms for whisper's initial prompt, capped so it cannot
    /// overflow `n_text_ctx/2` and silently degrade transcription.
    public func whisperPrompt(maxCharacters: Int = 400) -> String
    /// The glossary clause appended to the cleanup prompt.
    public func glossaryClause() -> String
}
```

- [ ] **Step 1:** Write failing tests: round-trip, duplicate terms are rejected case-insensitively, `whisperPrompt` caps and never truncates mid-term, `glossaryClause` is empty with no terms.
- [ ] **Step 2–5:** verify failure, implement, verify pass, commit — `feat: dictionary and snippet store`

---

## Task 2: Snippet expansion

**Produces:**
```swift
public enum SnippetExpander {
    public static func expand(_ text: String, with snippets: [Snippet]) -> String
}
```

Triggers match case-insensitively, on word boundaries, and tolerate the
punctuation cleanup adds. Longest trigger wins, so "my work email" beats
"my email". Expansion is a single pass — an expansion containing another
trigger is not re-expanded, because that is how you get a loop.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("expands a trigger") // "send it to my email" -> the address
@Test("is case-insensitive")
@Test("tolerates trailing punctuation cleanup added")
@Test("the longest trigger wins")
@Test("does not match inside a word")
@Test("expansion is single-pass, so a self-referential snippet cannot loop")
@Test("Arabic triggers expand")
@Test("no snippets means the text is returned untouched")
```

- [ ] **Step 2–5:** verify failure, implement, verify pass, commit — `feat: snippet expansion`

---

## Task 3: Two-layer injection

**Files:** `WhisperCppEngine.swift`, `CleanupProvider.swift`, `RoutedCleanup.swift`, `DictationController.swift`.

Layer 1 — `whisper-cli --prompt "<terms>"`, which biases decoding *before* it goes
wrong. Measured: fixed *Walid→Waleed* and *Kanji→Kandji*.

Layer 2 — the glossary clause appended to the cleanup prompt, catching what layer 1
misses. Measured: *Sala→Salla*, which layer 1 did not rescue.

Both are needed; either alone leaves errors.

- [ ] **Step 1:** `WhisperCppEngine` gains `initialPrompt: String`; passed as `--prompt` only when non-empty.
- [ ] **Step 2:** `RoutedCleanup` gains a `glossary: String` appended to the prompt it hands each provider.
- [ ] **Step 3:** `DictationController` gains `vocabulary: (() -> VocabularySnapshot)?` so it can read terms and snippets at dictation time without owning the store.
- [ ] **Step 4:** Tests assert the prompt reaches the process arguments and the glossary reaches the request body.
- [ ] **Step 5:** Live test with the real model, asserting the dictionary changes the transcript.
- [ ] **Step 6: Commit** — `feat: inject dictionary terms into both whisper and cleanup`

---

## Task 4: Suggestions from your own history

**Produces:**
```swift
public enum TermSuggester {
    public static func suggestions(from entries: [HistoryEntry],
                                   known: [DictionaryTerm],
                                   minimumOccurrences: Int = 3) -> [TermSuggestion]
}
public struct TermSuggestion: Sendable, Equatable, Identifiable {
    public var id: String { token }
    public let token: String
    public let occurrences: Int
}
```

A candidate is a token that recurs, is not a common word, is not already known, and
is at least four characters. Capitalised mid-sentence tokens rank first — proper
nouns are what whisper mangles, and they are what you want in the dictionary.

- [ ] **Step 1:** Failing tests: recurrence threshold, stopwords excluded, known terms excluded, case-insensitive dedupe, Arabic tokens, ranking.
- [ ] **Step 2–5:** verify failure, implement, verify pass, commit — `feat: suggest dictionary terms from recurring words in history`

---

## Task 5: The screens

**Files:** `VocabularyView.swift`, `MainWindow.swift`, `HistoryView.swift`.

- Dictionary: term list, add, delete, suggestions strip, and the measured evidence table behind the **ⓘ**.
- Snippets: trigger → expansion list, add, delete.
- The rail grows to History · Dictionary · Snippets.
- **History gains "Add to dictionary"** on a row, which is the user-initiated
  correction path that replaces the auto-learn we cannot build.

- [ ] **Step 1–4:** build, wire, install, verify by hand.
- [ ] **Step 5: Commit** — `feat: dictionary and snippets screens`

---

## Manual verification

- [ ] Add "Salla" to the dictionary; dictate a sentence containing it; it comes out right
- [ ] Add a snippet "my email"; say it mid-sentence; the address appears
- [ ] Say a snippet trigger inside a longer word — it does not expand
- [ ] An Arabic snippet expands
- [ ] Dictate the same mangled proper noun three times; it appears as a suggestion
- [ ] Accept a suggestion; it becomes a term
- [ ] "Add to dictionary" from a History row works
- [ ] Both screens render in light and dark

---

## Self-Review Notes

**Spec coverage.** §6 Dictionary → Tasks 1, 3, 4, 5. §6 Snippets → Tasks 1, 2, 5.
§5 Destinations is Phase 5; §7 Transforms and Insights are Phase 6.

**Type consistency.** `DictionaryTerm` and `Snippet` (Task 1) are consumed by
`SnippetExpander` (Task 2), the injection path (Task 3), `TermSuggester` (Task 4)
and `VocabularyView` (Task 5). `HistoryEntry` comes from Phase 3. `RawiColors` and
`ResolvedAppearance` from Phase 2. No orphans.

**Known gap, stated in the plan rather than buried.** Auto-learn from observed
corrections is not buildable without Accessibility. Suggestion plus one-click
confirmation is what ships, and the design canvas should be updated to match
rather than left promising something the app cannot do.
