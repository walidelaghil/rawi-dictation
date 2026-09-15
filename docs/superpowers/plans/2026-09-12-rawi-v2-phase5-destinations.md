# Rawi v2 · Phase 5 — Destinations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The same voice comes out shaped for where it lands — a Jira ticket, a Slack DM, a commit message.

**Architecture:** Two signals, both verified available on this machine: the frontmost app's bundle identifier (free) and, for browsers, the active tab URL via Automation (**0.16 s**, no administrator needed). A pure matcher picks the most specific rule, and that rule's instruction is appended to the cleanup prompt. `CleanupGuard` still runs, so a rule can restructure but cannot quietly drop what you said.

**Tech Stack:** Swift 6.3, AppleScript via `NSAppleScript`, SwiftUI.

## Global Constraints

- Deployment target **macOS 14.0**; Swift tools **6.0**; strict concurrency.
- **Zero third-party Swift dependencies.**
- Every task ends green: `swift build` and `swift test` both succeed.
- **No view hardcodes a colour** — everything through `RawiColors`.
- **No admin-gated permission.** Automation is user-approvable; Accessibility and Screen Recording are not, and must not be required.
- Reading the URL **must not block the start of a recording.** It is captured at key-press with a hard timeout; a slow or unscriptable browser costs the rule, never the dictation.
- Rules change **structure, register and punctuation**. They never add facts. `CleanupGuard` stays in force — measured: it rejects a cleanup that loses more than 30% of your words, and a destination rule is not an exemption.
- **Commands is out of scope.** See `docs/BACKLOG.md`.

## What the signals can and cannot do

Measured on this machine, not assumed:

| Signal | Mechanism | Cost | Status |
|---|---|---|---|
| Which app | `NSWorkspace.frontmostApplication` | none | ✅ |
| Which page | browser tab URL via Automation | one consent click per browser, 0.16 s | ✅ |
| Which window | `kCGWindowName` | Screen Recording | ❌ 0 of 12 titles readable |
| Which field | Accessibility API | Accessibility | ❌ cannot be granted |

So Jira vs Google Docs vs a Slack DM is distinguishable. *Which box inside Jira* is not, and no amount of design work changes that.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/RawiCore/Destinations/DestinationRule.swift` | **Create.** A rule, the defaults, and the store |
| `Sources/RawiCore/Destinations/DestinationMatcher.swift` | **Create.** Pure: which rule wins |
| `Sources/RawiCore/Destinations/BrowserContext.swift` | **Create.** Active tab URL, with a timeout |
| `Sources/RawiCore/App/DictationController.swift` | **Modify.** Capture and apply the destination |
| `Sources/RawiCore/UI/DestinationsView.swift` | **Create.** The screen |
| `Tests/RawiTests/DestinationMatcherTests.swift` | **Create.** |
| `Tests/RawiTests/DestinationRuleTests.swift` | **Create.** |

---

## Task 1: Rules and defaults

**Produces:**
```swift
public struct DestinationRule: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var bundleIDs: [String]     // empty = any app
    public var urlPattern: String?     // glob, nil = any page
    public var instruction: String
    public var enabled: Bool
    public var isBuiltIn: Bool
}

public final class DestinationStore: @unchecked Sendable {
    public init(url: URL = DestinationStore.defaultURL)
    public var rules: [DestinationRule] { get }
    public func add(_ rule: DestinationRule)
    public func remove(_ id: UUID)
    public func setEnabled(_ id: UUID, _ enabled: Bool)
    public static var defaults: [DestinationRule]
}
```

Shipped defaults: Jira ticket, Google Docs, Slack DM, Slack, commit message
(Terminal · iTerm · Xcode), Mail. Every instruction is about **shape and
register** — never about content, because the guard would reject that and
should.

- [x] **Step 1:** Failing tests — defaults exist and are enabled, round-trip, a user rule can be added and removed, built-ins can be disabled but not deleted.
- [x] **Step 2–5:** verify failure, implement, verify pass, commit.

---

## Task 2: Matching

**Produces:**
```swift
public enum DestinationMatcher {
    public static func match(bundleID: String?, url: String?,
                             rules: [DestinationRule]) -> DestinationRule?
    static func globMatches(_ pattern: String, _ value: String) -> Bool
}
```

**Specificity wins, and it is ordered deliberately:** a rule with both a bundle
and a URL pattern beats a URL-only rule, which beats a bundle-only rule. Within
the same tier, the longer URL pattern wins — so `…/client/*/D*` (a Slack DM)
beats `…/client/*` (any Slack), which is the entire reason DMs can be treated
differently.

- [x] **Step 1: Write the failing tests**

```swift
@Test("a bundle-only rule matches its app")
@Test("a URL pattern beats a bundle-only rule")
@Test("a longer URL pattern wins — a Slack DM is not just Slack")
@Test("a disabled rule never matches")
@Test("no match returns nil rather than a default")
@Test("a nil URL cannot match a URL rule")
@Test("globs match at both ends and in the middle")
@Test("a glob is anchored, so slack.com does not match evilslack.com")
```

- [x] **Step 2–5:** verify failure, implement, verify pass, commit.

---

## Task 3: The browser URL

**Produces:**
```swift
public enum BrowserContext {
    public static let scriptable: [String: String]   // bundleID -> AppleScript
    public static func activeURL(bundleID: String?, timeout: TimeInterval = 0.5) -> String?
    public static var lastError: String? { get }
}
```

Verified: Chrome answers in **0.16 s**. The timeout exists for the case where a
browser is busy or has no window — measured error `-1719` — where the right
answer is no rule, not a stalled dictation.

- [x] **Step 1:** Failing tests — a non-browser bundle returns nil without running a script; an unknown bundle returns nil; the scriptable map covers Chrome, Safari, Arc, Edge, Brave.
- [x] **Step 2:** Implement with `NSAppleScript` on a background queue and a hard timeout.
- [x] **Step 3:** A live test, skipped unless a browser with a window is running.
- [x] **Step 4–5:** verify, commit.

---

## Task 4: Apply it

**Files:** `DictationController.swift`, `AppDelegate.swift`.

- [x] **Step 1:** Controller gains `destination: ((String?) -> DestinationRule?)?`, resolved at key-press alongside the app and vocabulary.
- [x] **Step 2:** The matched instruction is appended to the cleanup prompt, after the glossary.
- [x] **Step 3:** `HistoryEntry` gains `destination: String?` so history shows which rule shaped it.
- [x] **Step 4:** Failing tests — the instruction reaches the prompt; no match means no change; the guard still rejects a rule-driven cleanup that loses the dictation.
- [x] **Step 5–6:** verify, commit.

---

## Task 5: The screen

**Files:** `DestinationsView.swift`, `MainWindow.swift`.

Rule list with match, instruction and an enable toggle; the three-tier capability
note behind the **ⓘ**; the rail grows to four.

- [x] **Step 1–4:** build, wire, install, verify by hand, commit.

---

## Manual verification

- [x] Dictate into Slack — output is one short paragraph, no sign-off
- [x] Dictate into a Jira ticket in Chrome — the first Automation prompt appears; allow it; output is structured
- [x] Dictate into a Slack **DM** — shorter than a channel message
- [x] Dictate in Terminal — imperative mood, short first line
- [x] Disable a rule — output reverts to plain cleanup
- [x] History shows which destination shaped each entry
- [x] Deny the Automation prompt — dictation still works, no rule applied, no hang

---

## Self-Review Notes

**Spec coverage.** §5 Destinations → Tasks 1–5. §7 Transforms and Insights are
Phase 6.

**Type consistency.** `DestinationRule` (Task 1) is consumed by
`DestinationMatcher` (Task 2), the controller (Task 4) and the view (Task 5).
`BrowserContext` (Task 3) is consumed only by the app delegate. `HistoryEntry`
(Phase 3) gains one optional field, decoded tolerantly so existing history loads.

**Known gap, accepted.** Field-level awareness is impossible here and is recorded
in `docs/BACKLOG.md` rather than half-built.
