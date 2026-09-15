# Rawi v2 · Phase 3 — Memory

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nothing you dictate is ever lost. A durable, searchable history, and the app window that shows it.

**Architecture:** Append-only JSONL on disk, loaded into memory for search — 500 entries is nothing to hold or scan, so there is no database and no index. Search is a pure function over entries, covering *both* the cleaned text and what whisper actually heard, because you remember what you said rather than what came out. The window is a SwiftUI `Window` with a left rail that grows as later phases land.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, JSONL.

## Global Constraints

- Deployment target **macOS 14.0**; Swift tools **6.0**; strict concurrency.
- **Zero third-party Swift dependencies.** No SQLite, no Core Data — JSONL is enough for 500 rows and stays greppable.
- Every task ends green: `swift build` and `swift test` both succeed before the commit.
- **No view hardcodes a colour.** Everything through `RawiColors` — the Phase 2 rule still holds.
- **No permission may be newly required.**
- **Privacy is a default, not a setting to find.** Capped at 500 entries; an app-exclusion list ships non-empty; a one-click purge exists.
- History records what was *inserted*, plus what whisper heard. It never records audio.
- **Commands is out of scope.** See `docs/BACKLOG.md`.
- The rail shows only what is built. A greyed-out row for an unbuilt phase is dead UI.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/RawiCore/History/HistoryEntry.swift` | **Create.** One record, Codable |
| `Sources/RawiCore/History/HistoryStore.swift` | **Create.** Append, load, cap, purge |
| `Sources/RawiCore/History/HistorySearch.swift` | **Create.** Pure filter over entries |
| `Sources/RawiCore/UI/HistoryView.swift` | **Create.** The searchable list |
| `Sources/RawiCore/UI/MainWindow.swift` | **Create.** Window shell and left rail |
| `Sources/RawiCore/Config/Config.swift` | **Modify.** Add `history` settings |
| `Sources/RawiCore/App/DictationController.swift` | **Modify.** Record each insertion |
| `Sources/Rawi/AppDelegate.swift` | **Modify.** Own the store, open the window |
| `Tests/RawiTests/HistoryStoreTests.swift` | **Create.** |
| `Tests/RawiTests/HistorySearchTests.swift` | **Create.** |

---

## Task 1: The record and its settings

**Files:** Create `HistoryEntry.swift`; modify `Config.swift`; test in `HistoryStoreTests.swift`.

**Produces:**
```swift
public struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let at: Date
    public let cleaned: String        // what was inserted
    public let raw: String            // what whisper heard
    public let script: Script
    public let appName: String?       // "Slack"
    public let bundleID: String?      // "com.tinyspeck.slackmacgap"
    public let durationSeconds: Double
    public let peakLevel: Double
    public let guardRejected: Bool    // cleanup was discarded, raw used
    public var wasCleaned: Bool { cleaned != raw }
    public var timestamp: String      // "14:05"
    public var day: String            // "12 Sep"
}

public struct HistorySettings: Codable, Sendable, Equatable {
    public var enabled: Bool          // true
    public var limit: Int             // 500
    public var excludedBundleIDs: [String]
}
```
`Config` gains `public var history: HistorySettings`.

**Exclusions ship non-empty.** A password manager and a private-message client
are where a plaintext log is a genuine liability, so `1Password` and `Messages`
are excluded out of the box rather than waiting for the user to think of it.

- [x] **Step 1: Write the failing tests**

```swift
@Suite("HistoryEntry") struct HistoryEntryTests {
    func entry(cleaned: String = "Cleaned.", raw: String = "raw") -> HistoryEntry {
        HistoryEntry(at: Date(), cleaned: cleaned, raw: raw, script: .latin,
                     appName: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                     durationSeconds: 3.2, peakLevel: 0.4, guardRejected: false)
    }

    @Test("round-trips through JSON") func codable() throws {
        let e = entry()
        let back = try JSONDecoder().decode(HistoryEntry.self,
                                            from: try JSONEncoder().encode(e))
        #expect(back == e)
    }

    @Test("knows whether cleanup changed anything") func wasCleaned() {
        #expect(entry(cleaned: "A", raw: "a").wasCleaned)
        #expect(!entry(cleaned: "same", raw: "same").wasCleaned)
    }

    @Test("defaults exclude a password manager and private messages") func exclusions() {
        let excluded = Config.default.history.excludedBundleIDs
        #expect(excluded.contains { $0.contains("1password") })
        #expect(excluded.contains { $0.contains("MobileSMS") || $0.contains("Messages") })
    }

    @Test("history is on by default and capped") func defaults() {
        #expect(Config.default.history.enabled)
        #expect(Config.default.history.limit == 500)
    }

    @Test("a config predating the key still loads") func backCompat() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"fn"}"#.utf8))
        #expect(c.history.enabled)
    }
}
```

- [x] **Step 2: Run to verify failure.** - [x] **Step 3: Implement.**
- [x] **Step 4: Run tests.** - [x] **Step 5: Commit** — `feat: history record and settings, with exclusions on by default`

---

## Task 2: The store

**Files:** Create `HistoryStore.swift`; test `Tests/RawiTests/HistoryStoreTests.swift`.

**Produces:**
```swift
public final class HistoryStore: @unchecked Sendable {
    public init(url: URL = HistoryStore.defaultURL, limit: Int = 500)
    public static var defaultURL: URL            // …/Application Support/Rawi/history.jsonl
    public func append(_ entry: HistoryEntry)
    public func all() -> [HistoryEntry]          // newest first
    public func purge()
    public func remove(_ id: UUID)
    public var count: Int { get }
}
```

**Why JSONL and not a database:** appends are a single line, the file stays
readable with `tail`, and a corrupt line costs one entry rather than the file.
At 500 rows, loading and scanning in memory is free.

**A corrupt line must never take the file down.** Decoding skips what it cannot
parse and keeps going — a truncated write during a crash should cost the last
dictation, not the history.

- [x] **Step 1: Write the failing tests**

```swift
@Suite("HistoryStore") struct HistoryStoreTests {
    func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-hist-\(UUID().uuidString).jsonl")
    }
    func entry(_ text: String, at: Date = Date()) -> HistoryEntry {
        HistoryEntry(at: at, cleaned: text, raw: text.lowercased(), script: .latin,
                     appName: "Slack", bundleID: "x", durationSeconds: 1,
                     peakLevel: 0.3, guardRejected: false)
    }

    @Test("appends survive a reload") func persists() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let a = HistoryStore(url: url); a.append(entry("one")); a.append(entry("two"))
        #expect(HistoryStore(url: url).all().count == 2)
    }

    @Test("newest comes first") func order() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url)
        s.append(entry("older", at: Date(timeIntervalSince1970: 1000)))
        s.append(entry("newer", at: Date(timeIntervalSince1970: 2000)))
        #expect(s.all().first?.cleaned == "newer")
    }

    @Test("the cap is enforced and drops the oldest") func cap() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url, limit: 5)
        for i in 0..<9 { s.append(entry("e\(i)", at: Date(timeIntervalSince1970: Double(i)))) }
        let all = s.all()
        #expect(all.count == 5)
        #expect(all.first?.cleaned == "e8")
        #expect(!all.contains { $0.cleaned == "e0" })
    }

    @Test("a corrupt line costs one entry, not the file") func corrupt() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url); s.append(entry("good one"))
        // Simulate a truncated write from a crash.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"id\":\"broke\n".utf8))
        try handle.close()
        let reloaded = HistoryStore(url: url)
        #expect(reloaded.all().count == 1)
        #expect(reloaded.all().first?.cleaned == "good one")
    }

    @Test("purge empties both memory and disk") func purge() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url); s.append(entry("one"))
        s.purge()
        #expect(s.all().isEmpty)
        #expect(HistoryStore(url: url).all().isEmpty)
    }

    @Test("a single entry can be removed") func remove() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url)
        s.append(entry("keep")); s.append(entry("drop"))
        let id = s.all().first { $0.cleaned == "drop" }!.id
        s.remove(id)
        #expect(s.all().map(\.cleaned) == ["keep"])
        #expect(HistoryStore(url: url).all().count == 1)
    }

    @Test("a missing file is an empty history, not a crash") func missing() {
        #expect(HistoryStore(url: tmp()).all().isEmpty)
    }

    @Test("newlines in a transcript cannot corrupt the format") func embeddedNewlines() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url)
        s.append(entry("line one\nline two"))
        #expect(HistoryStore(url: url).all().first?.cleaned == "line one\nline two")
    }
}
```

- [x] **Step 2–5:** verify failure, implement, verify pass, commit — `feat: append-only history store that survives a corrupt line`

---

## Task 3: Search

**Files:** Create `HistorySearch.swift`; test `Tests/RawiTests/HistorySearchTests.swift`.

**Produces:**
```swift
public struct HistoryFilter: Sendable, Equatable {
    public var query: String
    public var script: Script?
    public var bundleID: String?
    public init(query: String = "", script: Script? = nil, bundleID: String? = nil)
    public var isEmpty: Bool
}

public enum HistorySearch {
    public static func apply(_ filter: HistoryFilter, to entries: [HistoryEntry]) -> [HistoryEntry]
    /// True when the query matched the raw transcript but not the cleaned text —
    /// the UI shows the raw line in that case, so the match is visible.
    public static func matchedRawOnly(_ query: String, _ entry: HistoryEntry) -> Bool
}
```

**Search covers raw *and* cleaned.** You remember what you said, not what came
out — if cleanup removed "basically", searching for it must still find the entry.

- [x] **Step 1: Write the failing tests**

```swift
@Suite("HistorySearch") struct HistorySearchTests {
    func e(_ cleaned: String, _ raw: String, script: Script = .latin,
           bundle: String = "com.slack") -> HistoryEntry {
        HistoryEntry(at: Date(), cleaned: cleaned, raw: raw, script: script,
                     appName: "App", bundleID: bundle, durationSeconds: 1,
                     peakLevel: 0.3, guardRejected: false)
    }
    var corpus: [HistoryEntry] {
        [e("Ship the release on Friday.", "um ship the release on friday basically"),
         e("يعني لازم نأجل الاجتماع", "يعني لازم نأجل الاجتماع", script: .arabic),
         e("The deploy failed again.", "the deploy failed again", bundle: "com.apple.dt.Xcode")]
    }

    @Test("an empty query returns everything") func empty() {
        #expect(HistorySearch.apply(HistoryFilter(), to: corpus).count == 3)
    }

    @Test("matches the cleaned text") func cleaned() {
        #expect(HistorySearch.apply(HistoryFilter(query: "release"), to: corpus).count == 1)
    }

    @Test("matches a filler word that cleanup removed") func rawOnly() {
        // You remember what you said, not what came out.
        let hits = HistorySearch.apply(HistoryFilter(query: "basically"), to: corpus)
        #expect(hits.count == 1)
        #expect(HistorySearch.matchedRawOnly("basically", hits[0]))
    }

    @Test("is case-insensitive") func caseInsensitive() {
        #expect(HistorySearch.apply(HistoryFilter(query: "SHIP"), to: corpus).count == 1)
    }

    @Test("finds Arabic") func arabic() {
        #expect(HistorySearch.apply(HistoryFilter(query: "الاجتماع"), to: corpus).count == 1)
    }

    @Test("filters by script") func script() {
        #expect(HistorySearch.apply(HistoryFilter(script: .arabic), to: corpus).count == 1)
        #expect(HistorySearch.apply(HistoryFilter(script: .latin), to: corpus).count == 2)
    }

    @Test("filters by app") func app() {
        #expect(HistorySearch.apply(HistoryFilter(bundleID: "com.apple.dt.Xcode"),
                                    to: corpus).count == 1)
    }

    @Test("query and filter compose") func compose() {
        let f = HistoryFilter(query: "deploy", bundleID: "com.slack")
        #expect(HistorySearch.apply(f, to: corpus).isEmpty)
    }

    @Test("whitespace-only is treated as empty") func whitespace() {
        #expect(HistorySearch.apply(HistoryFilter(query: "   "), to: corpus).count == 3)
    }

    @Test("no match is an empty result, not everything") func noMatch() {
        #expect(HistorySearch.apply(HistoryFilter(query: "zzzz"), to: corpus).isEmpty)
    }
}
```

- [x] **Step 2–5:** verify failure, implement, verify pass, commit — `feat: history search across both cleaned and raw text`

---

## Task 4: The window

**Files:** Create `MainWindow.swift` and `HistoryView.swift`; modify `MenuBarController.swift`.

**Produces:**
```swift
@MainActor public final class MainWindow {
    public init(store: HistoryStore, appearance: ResolvedAppearance)
    public func show()
    public func setAppearance(_ appearance: ResolvedAppearance)
    public func reload()
}
```

Left rail per the design, but **only History** — later phases add their own rows.
A greyed row for an unbuilt screen is dead UI that teaches the user to ignore the rail.

The History screen: a search field, script and app filters, and rows showing the
cleaned text with the raw line beneath. The **ⓘ** beside the title holds the
explanation, per the approved design. Copy re-copies; delete removes one entry.

- [x] **Step 1: Build the window and view.**
- [x] **Step 2:** Wire the menu's Settings gear to add **Open Rawi**, and make it show the window.
- [x] **Step 3:** `make install`, open the window, confirm it lists real dictations.
- [x] **Step 4: Commit** — `feat: app window with searchable history`

---

## Task 5: Record every dictation

**Files:** Modify `DictationController.swift`, `AppDelegate.swift`.

- [x] **Step 1: Write the failing tests**

```swift
@MainActor @Suite("History recording") struct HistoryRecordingTests {
    @Test("an inserted dictation is written to the store") func records() async { … }
    @Test("an excluded app is not recorded at all") func excluded() async { … }
    @Test("a guard rejection is recorded as such") func guardFlag() async { … }
    @Test("history disabled means nothing is written") func disabled() async { … }
}
```
`DictationController` gains `public var onRecord: ((HistoryEntry) -> Void)?`, fired
only after a successful insertion — the same rule Phase 2's Recent uses.

- [x] **Step 2–4:** verify failure, implement, verify pass.
- [x] **Step 5:** Frontmost app name and bundle ID come from `NSWorkspace`, captured at key-press. No permission needed.
- [x] **Step 6: Commit** — `feat: record every inserted dictation to history`

---

## Manual verification

- [x] Dictate three times; open the window; all three are listed, newest first
- [x] Search a filler word that cleanup removed — the entry is found and the raw line shown
- [x] Search in Arabic — it matches
- [x] Filter by app and by language
- [x] Copy re-copies; ⌘V pastes it
- [x] Dictate into 1Password — **nothing is recorded**
- [x] Purge empties the list and the file
- [x] Switch to Light — the window follows, the pill stays dark
- [x] Quit and relaunch — history is still there

---

## Self-Review Notes

**Spec coverage.** §6 History → Tasks 1–5. §4 window → Task 4. §6 Dictionary and
Snippets are Phase 4; §5 Destinations is Phase 5 — the `bundleID` captured here is
the groundwork for it but no rules are applied yet.

**Type consistency.** `HistoryEntry` (Task 1) is consumed by `HistoryStore`
(Task 2), `HistorySearch` (Task 3), `HistoryView` (Task 4) and
`DictationController.onRecord` (Task 5). `HistoryFilter` (Task 3) is consumed only
by `HistoryView`. `Script` comes from Phase 1, `RawiColors` and
`ResolvedAppearance` from Phase 2. No orphans.

**Known gap, accepted.** Nothing here asserts what the window looks like. The
manual checklist covers it, as in Phase 2.
