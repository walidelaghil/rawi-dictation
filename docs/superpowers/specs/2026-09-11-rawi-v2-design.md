# Rawi v2 — Design

**Date:** 2026-09-11
**Status:** Approved (direction A + light mode; Commands deferred)
**Supersedes:** parts of `2026-09-09-whisperflow-dictation-design.md` — that spec
still governs audio capture, the cleanup guard, the hotkey backends and the
permission model, none of which change here.

## 1. What v2 changes

v1 works: hold `⌥Space`, speak, `⌘V`. It is English-only, has no memory, and
knows nothing about where the text is going. v2 fixes those three, and gives the
app a real surface.

**One hotkey, both languages.** Today Arabic does not degrade — it *fails*,
because `ggml-small.en` is English-only. v2 replaces per-language hotkeys with a
single key and automatic detection.

**It remembers.** A searchable history, a dictionary that learns, and snippets.

**It knows where the text lands.** App identity and browser page, mapped to tone.

**It has a face.** A menu-bar control, a redesigned pill, and an app window — in
dark *and* light.

Not in v2: **Commands / speech-to-action.** Designed, deliberately deferred, with
the reasoning in [`docs/BACKLOG.md`](../../BACKLOG.md). No menu item, no nav
entry, no config key.

## 2. Language: one key, one model

Measured on this M4, warm:

| | Transcribe | Cleanup | Total |
|---|---|---|---|
| v1 English path (`small.en` + `qwen2.5:1.5b`) | 0.63 s | 0.81 s | 1.44 s |
| v2 universal (`large-v3-turbo-q5_0 -l auto`) | ~1.96 s | ~0.83 s | ~2.79 s |

v2 costs **~1.4 s** on English and buys one key plus genuine Arabic and mixed
speech. Accepted deliberately: the two-key interaction was rejected as a worse
trade than the latency.

Language detection is **not** a cheap pre-pass — `-dl` costs 1.9–2.8 s because it
loads the model anyway. So there is no detect-then-route optimisation: one model,
always `-l auto`, detection free as part of transcription.

**Cleanup is routed by script, invisibly.** This is not a preference — it is a
correctness requirement. Measured: `qwen2.5:1.5b` *translates Arabic into English*
and cannot be instructed out of it (it was told explicitly and ignored it), while
`qwen2.5:3b` is correct on Arabic and mixed but leaves fillers in English.

    transcript contains Arabic script  →  qwen2.5:3b
    otherwise                          →  qwen2.5:1.5b

Deterministic, zero-cost, no model involved in the decision. **No user-visible
setting.** v1's `engine` config key stays for the API providers; the local model
is no longer a choice the user makes.

`CleanupGuard` needs no change — it is word-overlap based and therefore
script-agnostic. Verified against the Arabic failure: a translated transcript
retains 0–7% of the dictated words and is rejected; a correctly cleaned one
retains 87–100% and passes.

## 3. Theme

Three states, matching macOS: `system` (default), `dark`, `light`. Toggled from
the menu bar and stored as `appearance` in config.

**A semantic token layer is mandatory.** Every surface reads from `RawiColors`,
which resolves each token per appearance. No view may hardcode a colour — that is
what keeps two themes in sync rather than one theme plus a broken copy.

| Token | Role |
|---|---|
| `ink` / `surface` / `raised` / `edge` | grounds and borders |
| `bone` / `muted` / `faint` | text, three weights |
| `saffron` | live — recording |
| `verdigris` | finished — inserted, accepted |
| `lapis` | detected language, secondary state |
| `clay` | guard rejection, error |

Accents share chroma and lightness and vary only in hue, so no one of them shouts
over the others. The pill is the one surface that does **not** follow the system
in `system` mode: it stays dark in both, because it floats over arbitrary app
content and a light pill on a light document disappears. That is a deliberate
exception, not an oversight.

## 4. Surfaces

### Menu bar — the primary control
One surface, no nested cards, sections divided by hairlines:

- **Live block** — state, level meter, detected language
- **Action row** — three cells, each an icon and its shortcut side by side; the
  name appears on hover *and* on keyboard focus
- **Recent** — collapsed behind a disclosure
- **Footer** — Open Rawi · Quit

### Pill
Bottom-centre, **click-through by default**. A 30 Hz poll of
`NSEvent.mouseLocation` (unprivileged) makes it interactive only when the cursor
rests on it — which is what stops it stealing clicks from the app behind. States,
colour and copy per the `Pill` artboard.

### Window
Left rail plus content: Insights, History, Dictionary, Snippets, Destinations,
Transforms. Every screen's explanatory prose sits behind an **ⓘ** beside its
title, because that copy is scaffolding you stop needing. Structured reference
(the dictionary evidence table, the destination capability matrix) stays on screen.

## 5. Destination awareness

Three signals, and an honest ceiling — all three verified on this machine:

| Signal | Mechanism | Cost | Status |
|---|---|---|---|
| Which app | `NSWorkspace.frontmostApplication` | none | available |
| Which page | browser tab URL via Automation | one consent click, no admin | available |
| Which window | `kCGWindowName` | Screen Recording | **0 of 12 titles readable** |
| Which field | Accessibility API | Accessibility | **unavailable on this Mac** |

So Jira vs Google Docs vs a Slack DM is distinguishable; *which box inside Jira*
is not. Rules match on bundle identifier and an optional URL glob, and change
**formatting and register only** — they never add words that were not spoken.
That line is what `CleanupGuard` exists to hold.

## 6. Memory

**History** — every dictation: timestamp, app, URL host, language, raw transcript,
cleaned text, duration, peak level, and whether the guard fired. Searchable across
*both* raw and cleaned text. Capped at 500 entries; per-destination exclusions
(Slack DMs, 1Password) by default. Stored as JSONL under Application Support.

**Dictionary** — two layers, because measurement showed one is not enough:
the decoder hint fixed *Walid→Waleed* and *Kanji→Kandji* but not *Sala→Salla*,
which only the cleanup glossary caught. A term is added automatically after the
same correction is observed twice, and is marked as learned so it can be removed.

**Snippets** — spoken triggers expanded during dictation only, so unlike a
keyboard expander they cannot fire while typing.

## 7. Transforms

Copy text, hold `⌃⌥Space`, speak an instruction, get the rewrite on the clipboard.
Runs through the pasteboard rather than reading the selection, because reading
selected text needs Accessibility. The original always goes to History, so a bad
rewrite is never destructive.

Ships with Polish, **Turn this into a prompt**, Make it shorter, Translate to
Arabic, Reply in my tone. The prompt one matters most: it is the feature Lemon
pivoted *toward*, and it carries none of the execution risk that deferred Commands.

## 8. Phasing

Each phase ships something usable on its own.

1. **Language foundation** — one hotkey, `-l auto`, script-routed cleanup, model
   management. *Ships: Arabic works at all.*
2. **Shell** — theme tokens and the light/dark/system toggle, the new menu bar, the
   redesigned click-through pill. *Ships: the app looks like the design.*
3. **Memory** — history store, the window shell, searchable History. *Ships:
   nothing is ever lost.*
4. **Accuracy** — dictionary (two layers, auto-learn) and snippets. *Ships: your
   words come out right.*
5. **Context** — destinations by app and browser URL. *Ships: output fits where it
   lands.*
6. **Refine** — transforms, speech-to-prompt, insights.

## 9. Out of scope

Commands / speech-to-action · auto-paste · field-level destinations ·
learn-from-edits beyond the dictionary · streaming partial transcription ·
accounts, sync, telemetry of any kind · Windows or Linux.
