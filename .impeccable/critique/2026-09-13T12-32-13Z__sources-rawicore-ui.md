---
target: Rawi app UI (all screens and flows)
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
timestamp: 2026-09-13T12-32-13Z
slug: sources-rawicore-ui
---
Method: dual-agent (A: design review, isolated · B: detector + mechanical evidence, isolated)

# Design Health: 27/40

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | Every status surface self-destructs after 2.5s onto a hidden pill |
| 2 | Match System / Real World | 3 | Excellent copy except at failure, which prints error.localizedDescription |
| 3 | User Control and Freedom | 2 | No undo on either destructive path; delete-key removes a row with no confirmation while Clear all has one |
| 4 | Consistency and Standards | 2 | Shortcuts rebindable but hardcoded as glyph literals in five files |
| 5 | Error Prevention | 2 | Shipped defaults put dictate and transform on the same chord, invisibly |
| 6 | Recognition Rather Than Recall | 3 | Panel actions are icon + shortcut only; colour vocabulary has no legend |
| 7 | Flexibility and Efficiency | 4 | Genuinely excellent |
| 8 | Aesthetic and Minimalist Design | 3 | Insights leads with 55 empty squares; RowGroup stretches a one-row list over 870px |
| 9 | Error Recovery | 2 | No retry anywhere; retained WAV path exists only in a log file |
| 10 | Help and Documentation | 3 | Info overlays are the right model, and two contain broken sentences |
| Total | | 27/40 | Above average, held back by failure handling and control |

## Design Specificity Verdict

Split: the peripherals (menu bar mark, pill, Destinations) are unmistakably this product; the window is a competent generic Mac shell carrying product-specific content. Insights in particular is a stock usage-stats page with a contribution-graph streak imported from another product category.

Deterministic scan: the bundled detector ran twice, exit 0, output [] — it cannot read .swift (scannable extensions are HTML/CSS/JS-family), so it scanned zero of 20 files. Replaced with a mechanical scan:
- Design systems hold: 0 hardcoded font sizes (~110 .font calls), 0 hardcoded radii (40 sites), 0 em-dashes in UI strings, 1 middle dot.
- 2 icon-only destructive buttons with no accessible name (DestinationsView.swift:67, VocabularyView.swift:162).
- 0 of 91 user-visible strings localisable; no Dynamic Type anywhere.
- 9 fixed widths on text-bearing views; minimumScaleFactor used nowhere.
- 1 appearance-unaware colour (HistoryView.swift:177 shadow).
- False positives correctly flagged: RawiMark .black template path; 7 .dark pins for the menu-bar extra and app icon.

Visual overlays: not available (native app, no URL). Reported as skipped.

## Overall Impression

A trust-first tool that consistently states what it cannot do, with a well-made peak moment (text landing, mark spring, pill ending on your own words). It has no answer for the two moments after that: when it fails, and when it was wrong. Biggest opportunity: on this Mac the clipboard IS the product, and it is the one thing with no screen.

## What's Working

1. One glyph carries the whole state machine (RawiMark + MarkMotion, one timeline, repaints only when visibly different).
2. Trust is designed, not claimed (CleanupGuard, heard-line evidence, ESTIMATE with an editable assumption, BLOCKED card).
3. The hotkey clash reframed as an offer (refuse the write, name the conflict, propose the swap).

## Priority Issues

### [P0] The app displays shortcuts that are not the shortcuts, and the defaults collide
Config.default sets fallbackHotkey and transformHotkey to the same chord (Config.swift:257,259). With Carbon as the backend, dictate and transform share a key on a fresh install of the target machine class. SettingsView.value(for:.dictate) reads config.hotkey (SettingsView.swift:102), not the bound key, so the clash detector cannot see it. Five files print hardcoded glyph literals.
Fix: Config.effectiveDictateHotkey; route Settings and all display sites through HotkeyConfig.symbolic of it; change the transformHotkey default; run the clash check at load.
Command: /impeccable harden

### [P0] Failure has no surface and no recovery
.error clears after 2.5s onto a hidden pill; failures never reach History; the retained WAV path is log-only.
Fix: HistoryEntry.kind = .failed with error + audio URL and a Retry action; stop auto-clearing .error; keep the status item clay while an unacknowledged failure exists.
Command: /impeccable harden

### [P1] No undo at either destructive moment
Cleanup can rewrite meaning; a transform replaces the clipboard; delete-key removes a row with no confirmation while Clear all has one.
Fix: "Use what I said" row action when entry.wasCleaned; Undo on the transform notice; confirmation or undo for the delete key.
Command: /impeccable harden

### [P1] Contrast floor on the affordances that teach the product
Rail shortcut hints 2.11:1; search hint 2.95:1; faint body on raised 3.80:1 (carries the raw transcript, tile qualifiers, Settings descriptions).
Fix: lift dark .faint to ~#8E99A6 and light .faint to #5F6874; remove every .opacity() multiplier on a text token (MainWindow.swift:236, HistoryView.swift:207).
Command: /impeccable audit

### [P2] Insights inverts its priorities, and empty lists produce voids
Streak grid is largest and topmost, 55 empty squares at one day, and is the only frequency-rewarding metric in a tool whose value is being forgotten. RowGroup stretches, so a one-row list sits on ~870px of bordered emptiness.
Fix: tiles above streak; gate the grid behind >=7 active days, showing the AR/EN split until then; give RowGroup an intrinsic height.
Command: /impeccable layout

## Persona Red Flags

Power user: result loop is open (only Copy, of the mangled text); two disconnected recency models (panel Recent in-memory capped at 5 vs persisted History); no Cmd-, from the window; filter row unwrapped and unbounded, already showing two chips both labelled "Slack" because HistorySearch.apps dedupes by bundleID not name.

First-timer: no first-run anything; opening move is an unlabelled waveform glyph; panel teaches a hardcoded shortcut that may not be the binding; transform action is an unlabelled wand glyph; broken engine or missing Ollama produces a 2.5s red capsule with no pointer to Settings.

Bilingual professional on a locked-down Mac: config.example.json, committed as the verified-working configuration, pins ggml-small.en.bin with language "en" — the model FirstRunSetup documents as unable to serve Arabic; Settings does not mark whether a model is multilingual. The window chrome never mirrors. The heard-line renders raw Arabic monospaced at the smallest size at 3.8:1.

## Minor Observations

- Two info overlays contain broken sentences from the em-dash removal pass: InsightsView.swift:35 ("changes them change to match"), TransformsView.swift:82 (lowercase after a period).
- HistoryView.swift:167: ternary with identical branches printing a hardcoded 500 that ignores config.history.limit.
- "1 days used" — the tile does not pluralize while the streak label does.
- Two adjacent tiles both read "1m" with unrelated meanings; saved-versus-typing cannot equal total speaking time at 52 words.
- DesignTokens.swift promises three radius values and defines four.
- Light panel footer: c(.ink) on surface is 1.03:1.
- No accessibility story for the pill: marks hidden, meter unlabelled, panel cannot become key.

## Questions to Consider

1. If the mark can say "thinking" without a spinner, why not "your five minutes are still safe"?
2. Is "stays in plaintext on this Mac, 500 entries deep, forever" the promise "Stays on this Mac" meant?
3. If Accessibility can never be granted, the clipboard is the product. Why does it have no screen?
4. Dictionary and Snippets: two rail items, one file, one mental model. What does the split buy?
