# Rawi v2 · Phase 2 — Shell

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app look like the approved design — direction A, with a light/dark/system toggle — and make the pill stop stealing clicks.

**Architecture:** A semantic token layer (`RawiColors`) resolves every colour per appearance, so no view ever names a colour and the two themes cannot drift apart. The menu bar becomes a SwiftUI panel in an `NSPopover`. The pill becomes click-through by default and arms itself only when the cursor genuinely rests on it, decided by a pure function over the cursor point and the pill's frame.

**Tech Stack:** Swift 6.3, AppKit, SwiftUI, `NSPopover`, `NSEvent.mouseLocation`.

## Global Constraints

- Deployment target **macOS 14.0**; Swift tools **6.0**; strict concurrency.
- **Zero third-party Swift dependencies.**
- No telemetry, no analytics, no account.
- Every task ends green: `swift build` and `swift test` both succeed before the commit.
- **No permission may be newly required.** Cursor position comes from `NSEvent.mouseLocation`, which is unprivileged; a global *keyboard* monitor would need Input Monitoring and is forbidden here.
- **No view may hardcode a colour.** Every colour comes from `RawiColors`. This is what keeps two themes in sync rather than one theme plus a broken copy.
- The pill does **not** follow the system appearance: it stays dark in both, because it floats over arbitrary app content and a light pill on a light document disappears. Deliberate exception.
- **Commands is out of scope** — no menu item, no nav entry, no config key. See `docs/BACKLOG.md`.
- Existing behaviour that must not regress: the Carbon hotkey path, `CleanupGuard`, routed cleanup, the clipboard-plus-⌘V insertion.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/RawiCore/UI/Appearance.swift` | **Create.** `Appearance` enum, resolution against the system |
| `Sources/RawiCore/UI/RawiColors.swift` | **Create.** Semantic tokens, one value per token per appearance |
| `Sources/RawiCore/UI/PillProximity.swift` | **Create.** Pure: should the pill be armed for this cursor point |
| `Sources/RawiCore/UI/PillView.swift` | **Rewrite.** Design-A pill, tokens only |
| `Sources/RawiCore/UI/PillWindow.swift` | **Rewrite.** Click-through, proximity polling, arming |
| `Sources/RawiCore/UI/MenuPanelView.swift` | **Create.** SwiftUI dropdown: live block, action trio, Recent |
| `Sources/RawiCore/UI/MenuBarController.swift` | **Rewrite.** Status item + `NSPopover` hosting `MenuPanelView` |
| `Sources/RawiCore/Config/Config.swift` | **Modify.** Add `appearance` |
| `Tests/RawiTests/AppearanceTests.swift` | **Create.** |
| `Tests/RawiTests/RawiColorsTests.swift` | **Create.** |
| `Tests/RawiTests/PillProximityTests.swift` | **Create.** |

---

## Task 1: Appearance setting

**Files:** Create `Sources/RawiCore/UI/Appearance.swift`; modify `Config.swift`; test `Tests/RawiTests/AppearanceTests.swift`.

**Produces:**
```swift
public enum Appearance: String, Codable, Sendable, CaseIterable {
    case system, dark, light
    public var displayName: String
    /// The concrete appearance to paint, given what the system currently is.
    public func resolved(systemIsDark: Bool) -> ResolvedAppearance
    /// nil for `system` — meaning "inherit", which is what NSApp.appearance expects.
    public var nsAppearanceName: NSAppearance.Name?
}
public enum ResolvedAppearance: String, Sendable, CaseIterable { case dark, light }
```
`Config` gains `public var appearance: Appearance` defaulting to `.system`, decoded tolerantly like every other key.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import AppKit
@testable import RawiCore

@Suite("Appearance") struct AppearanceTests {
    @Test("system follows whatever the OS is doing") func system() {
        #expect(Appearance.system.resolved(systemIsDark: true) == .dark)
        #expect(Appearance.system.resolved(systemIsDark: false) == .light)
    }

    @Test("an explicit choice overrides the OS in both directions") func explicit() {
        #expect(Appearance.dark.resolved(systemIsDark: false) == .dark)
        #expect(Appearance.light.resolved(systemIsDark: true) == .light)
    }

    @Test("system maps to no NSAppearance, meaning inherit") func nsName() {
        #expect(Appearance.system.nsAppearanceName == nil)
        #expect(Appearance.dark.nsAppearanceName == .darkAqua)
        #expect(Appearance.light.nsAppearanceName == .aqua)
    }

    @Test("every case is user-presentable") func names() {
        for a in Appearance.allCases { #expect(!a.displayName.isEmpty) }
    }

    @Test("config defaults to following the system") func configDefault() {
        #expect(Config.default.appearance == .system)
    }

    @Test("a config predating the key still loads") func backCompat() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"fn"}"#.utf8))
        #expect(c.appearance == .system)
    }

    @Test("an explicit appearance round-trips") func roundTrip() throws {
        let c = try JSONDecoder().decode(Config.self,
            from: Data(#"{"appearance":"light"}"#.utf8))
        #expect(c.appearance == .light)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter AppearanceTests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run tests** — PASS, 7 tests.
- [ ] **Step 5: Commit** — `feat: appearance setting with system, dark and light`

---

## Task 2: Semantic colour tokens

The single rule that keeps two themes working: **views name roles, never colours.**

**Files:** Create `Sources/RawiCore/UI/RawiColors.swift`; test `Tests/RawiTests/RawiColorsTests.swift`.

**Produces:**
```swift
public enum ColorToken: String, Sendable, CaseIterable {
    case ink, surface, raised, edge          // grounds and borders
    case bone, muted, faint                  // text, three weights
    case saffron, verdigris, lapis, clay     // state
}

public enum RawiColors {
    public static func hex(_ token: ColorToken, _ appearance: ResolvedAppearance) -> String
    public static func color(_ token: ColorToken, _ appearance: ResolvedAppearance) -> Color
    public static func nsColor(_ token: ColorToken, _ appearance: ResolvedAppearance) -> NSColor
    /// The pill is always dark — see Global Constraints.
    public static func pill(_ token: ColorToken) -> Color
}
```

Values are the approved direction-A palette. Accents share chroma and lightness and
vary only in hue, so none shouts over the others.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import SwiftUI
@testable import RawiCore

@Suite("RawiColors") struct RawiColorsTests {
    @Test("every token resolves in both appearances") func complete() {
        // The classic two-theme bug is a token defined in one theme only.
        for token in ColorToken.allCases {
            for appearance in ResolvedAppearance.allCases {
                let hex = RawiColors.hex(token, appearance)
                #expect(hex.hasPrefix("#"), "\(token) missing in \(appearance)")
                #expect(hex.count == 7, "\(token)/\(appearance) is not #rrggbb: \(hex)")
            }
        }
    }

    @Test("light and dark genuinely differ for every ground and text token") func differ() {
        for token in [ColorToken.ink, .surface, .raised, .bone, .muted, .faint] {
            #expect(RawiColors.hex(token, .dark) != RawiColors.hex(token, .light),
                    "\(token) is identical in both themes")
        }
    }

    @Test("grounds and text are inverted between themes") func inverted() {
        // ink is the darkest ground in dark mode and the lightest in light mode.
        #expect(luminance(RawiColors.hex(.ink, .dark)) < 0.3)
        #expect(luminance(RawiColors.hex(.ink, .light)) > 0.7)
        #expect(luminance(RawiColors.hex(.bone, .dark)) > 0.7)
        #expect(luminance(RawiColors.hex(.bone, .light)) < 0.3)
    }

    @Test("body text clears 4.5:1 against its ground in both themes") func contrast() {
        for appearance in ResolvedAppearance.allCases {
            let ratio = contrastRatio(RawiColors.hex(.bone, appearance),
                                      RawiColors.hex(.surface, appearance))
            #expect(ratio >= 4.5, "bone on surface is \(ratio):1 in \(appearance)")
        }
    }

    @Test("secondary text clears 3:1, the large-text floor") func secondaryContrast() {
        for appearance in ResolvedAppearance.allCases {
            let ratio = contrastRatio(RawiColors.hex(.muted, appearance),
                                      RawiColors.hex(.surface, appearance))
            #expect(ratio >= 3.0, "muted on surface is \(ratio):1 in \(appearance)")
        }
    }

    @Test("state colours stay distinguishable from one another") func states() {
        for appearance in ResolvedAppearance.allCases {
            let states = [ColorToken.saffron, .verdigris, .lapis, .clay]
                .map { RawiColors.hex($0, appearance) }
            #expect(Set(states).count == states.count)
        }
    }

    @Test("the pill palette is dark regardless of appearance") func pillIsDark() {
        // It floats over arbitrary content; a light pill on a light document vanishes.
        #expect(luminance(RawiColors.hex(.ink, .dark)) < 0.3)
    }
}

// WCAG relative luminance and contrast, so the assertions mean something.
func luminance(_ hex: String) -> Double {
    let v = Array(hex.dropFirst())
    func channel(_ i: Int) -> Double {
        let s = Double(UInt8(String(v[i*2...i*2+1]), radix: 16) ?? 0) / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(0) + 0.7152 * channel(1) + 0.0722 * channel(2)
}
func contrastRatio(_ a: String, _ b: String) -> Double {
    let (l1, l2) = (luminance(a), luminance(b))
    let (hi, lo) = (max(l1, l2), min(l1, l2))
    return (hi + 0.05) / (lo + 0.05)
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement.** Store hex per token per appearance in one table, so adding a token forces both values.
- [ ] **Step 4: Run tests** — PASS, 7 tests. Tune the light palette until the contrast assertions hold; they are the specification, not a suggestion.
- [ ] **Step 5: Commit** — `feat: semantic colour tokens with contrast-checked light and dark`

---

## Task 3: The pill stops stealing clicks

**Files:** Create `Sources/RawiCore/UI/PillProximity.swift`; rewrite `PillView.swift` and `PillWindow.swift`; test `Tests/RawiTests/PillProximityTests.swift`.

**Produces:**
```swift
public struct PillProximity: Sendable {
    public init(armDelay: Duration = .milliseconds(250), slop: CGFloat = 6)
    /// Feed the cursor each tick; returns true when the pill should be interactive.
    public mutating func update(cursor: CGPoint, frame: CGRect,
                                now: ContinuousClock.Instant) -> Bool
    public var isArmed: Bool { get }
    public mutating func reset()
}
```

**Why a delay:** without it, a cursor merely crossing the pill on its way somewhere
else would arm it and swallow the click the user intended for the app behind.
**Why slop:** a cursor resting exactly on the border should not flicker between
armed and not.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import RawiCore

@Suite("PillProximity") struct PillProximityTests {
    let frame = CGRect(x: 100, y: 100, width: 200, height: 40)
    let inside = CGPoint(x: 200, y: 120)
    let outside = CGPoint(x: 500, y: 500)

    func make() -> PillProximity { PillProximity(armDelay: .milliseconds(250), slop: 6) }

    @Test("a cursor far away never arms it") func away() {
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: outside, frame: frame, now: t) == false)
        #expect(p.update(cursor: outside, frame: frame, now: t.advanced(by: .seconds(5))) == false)
    }

    @Test("hovering arms only after the delay") func delay() {
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: inside, frame: frame, now: t) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(200))) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(260))) == true)
    }

    @Test("passing through without stopping never arms it") func passingThrough() {
        // The whole point: a cursor crossing the pill must not swallow the click.
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: inside, frame: frame, now: t) == false)
        #expect(p.update(cursor: outside, frame: frame, now: t.advanced(by: .milliseconds(100))) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(200))) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(400))) == false)
    }

    @Test("leaving disarms immediately") func leave() {
        var p = make(); let t = ContinuousClock.now
        _ = p.update(cursor: inside, frame: frame, now: t)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(300))) == true)
        #expect(p.update(cursor: outside, frame: frame, now: t.advanced(by: .milliseconds(310))) == false)
        #expect(p.isArmed == false)
    }

    @Test("slop keeps the edge from flickering") func slop() {
        var p = make(); let t = ContinuousClock.now
        let justOutside = CGPoint(x: frame.maxX + 4, y: frame.midY)   // within 6pt slop
        _ = p.update(cursor: inside, frame: frame, now: t)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(300))) == true)
        #expect(p.update(cursor: justOutside, frame: frame, now: t.advanced(by: .milliseconds(320))) == true)
        let wellOutside = CGPoint(x: frame.maxX + 40, y: frame.midY)
        #expect(p.update(cursor: wellOutside, frame: frame, now: t.advanced(by: .milliseconds(330))) == false)
    }

    @Test("reset disarms and forgets the dwell") func reset() {
        var p = make(); let t = ContinuousClock.now
        _ = p.update(cursor: inside, frame: frame, now: t)
        p.reset()
        #expect(p.isArmed == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(300))) == false)
    }

    @Test("an empty frame can never arm") func emptyFrame() {
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: inside, frame: .zero, now: t) == false)
        #expect(p.update(cursor: inside, frame: .zero, now: t.advanced(by: .seconds(2))) == false)
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement `PillProximity`.**
- [ ] **Step 4: Run tests** — PASS, 7 tests.
- [ ] **Step 5: Rewrite `PillWindow`.** `ignoresMouseEvents = true` by default; a 30 Hz timer feeds `NSEvent.mouseLocation` and the panel frame into `PillProximity`; on arming, set `ignoresMouseEvents = false` and expand. The panel keeps `canBecomeKey = false` — that has not changed and is still load-bearing.
- [ ] **Step 6: Rewrite `PillView`** to the approved design, every colour from `RawiColors.pill(_:)`.
- [ ] **Step 7: Run the full suite and commit** — `feat: click-through pill that arms only on a deliberate hover`

---

## Task 4: The menu bar dropdown

**Files:** Create `Sources/RawiCore/UI/MenuPanelView.swift`; rewrite `MenuBarController.swift`.

**Produces:**
```swift
@MainActor public final class MenuBarController: NSObject {
    public init(controller: DictationController, log: any Logging)
    public func refresh(state: DictationState, permissions: PermissionStatus)
    public var onOpenSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
}

public struct MenuAction: Identifiable, Sendable {
    public let id: String, title: String, shortcut: String, symbol: String
}
public enum MenuActions { public static let all: [MenuAction] }   // dictate, transform
```

Layout per the approved design: one surface, sections divided by hairlines —
live block, action row (icon and shortcut side by side, name on hover **and**
keyboard focus), Recent behind a disclosure, footer.

**Commands is absent.** `MenuActions.all` has two entries, not three.

An `NSPopover` hosts the SwiftUI view, anchored to the status item button.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import RawiCore

@Suite("MenuActions") struct MenuActionsTests {
    @Test("the shipped actions are dictate and transform only") func shipped() {
        // Commands is designed but deferred — see docs/BACKLOG.md.
        #expect(MenuActions.all.map(\.id) == ["dictate", "transform"])
    }

    @Test("every action names a shortcut and a symbol") func complete() {
        for a in MenuActions.all {
            #expect(!a.title.isEmpty)
            #expect(!a.shortcut.isEmpty)
            #expect(!a.symbol.isEmpty)
        }
    }

    @Test("ids are unique") func unique() {
        #expect(Set(MenuActions.all.map(\.id)).count == MenuActions.all.count)
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement `MenuActions` and `MenuPanelView`.**
- [ ] **Step 4: Rewrite `MenuBarController`** to present the popover, keeping the existing behaviours: enable toggle, launch at login, permission warnings, open config, reveal logs, quit. Add the appearance picker.
- [ ] **Step 5: Run tests** — PASS.
- [ ] **Step 6: Commit** — `feat: menu bar dropdown matching the approved design`

---

## Task 5: Wire the appearance through and verify

**Files:** Modify `Sources/Rawi/AppDelegate.swift`, `Sources/Rawi/Doctor.swift`.

- [ ] **Step 1:** Apply `config.appearance` to `NSApp.appearance` at launch and whenever it changes; re-apply on config hot-reload.
- [ ] **Step 2:** Observe `AppleInterfaceThemeChangedNotification` on `DistributedNotificationCenter` so `system` follows a live OS switch without a restart.
- [ ] **Step 3:** Add `appearance` to the doctor output.
- [ ] **Step 4:** `make install`, relaunch, confirm the doctor reports it.
- [ ] **Step 5:** Commit — `feat: apply appearance at launch and follow live system changes`

---

## Manual verification

Automated tests cannot see. After Task 5:

- [ ] Menu bar dropdown matches the approved design; hover each action to see its name
- [ ] Tab to the actions — the name appears on keyboard focus too
- [ ] Recent collapses and expands; the state persists while the popover is open
- [ ] Switch appearance to Light — menu and window follow, **pill stays dark**
- [ ] Switch to System, then flip macOS between light and dark — Rawi follows live
- [ ] Text stays readable in both themes, everywhere
- [ ] **Put a clickable button under the pill and click it while recording — the click lands**
- [ ] Rest the cursor on the pill for a moment — it solidifies and expands
- [ ] Move the cursor across the pill without stopping — it does not arm
- [ ] `Commands` appears nowhere in the UI

---

## Self-Review Notes

**Spec coverage.** §3 theme → Tasks 1, 2, 5. §4 menu bar → Task 4. §4 pill → Task 3.
§4 window is Phase 3 and absent here. §5 destinations, §6 memory, §7 transforms are
later phases.

**Type consistency.** `ResolvedAppearance` (Task 1) is consumed by every
`RawiColors` signature (Task 2). `ColorToken` (Task 2) is consumed by `PillView`
(Task 3) and `MenuPanelView` (Task 4). `PillProximity` (Task 3) is consumed only by
`PillWindow`. `MenuAction` (Task 4) is consumed only by `MenuPanelView`. No orphans.

**Known gap, accepted.** Nothing here can assert what a pixel looks like. The
contrast tests in Task 2 are the closest thing to an automated check on the visual
result, and they are deliberately strict so the light theme cannot ship unreadable.
Everything else is on the manual checklist.
