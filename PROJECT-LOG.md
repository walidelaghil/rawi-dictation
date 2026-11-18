# Project log

Append only. Never edit or delete an earlier entry; correct it with a new one.
Written before a session ends and after every merge. Newest at the bottom.

Each entry: **Asked** (what you wanted) · **Decided** (and why) · **Shipped** (what changed).

---

## 2026-11-18 — Desktop app design critique, Snippets input

**Asked**
- Critique the desktop app's design and UX against Wispr Flow. Trigger: the Snippets "…type this" field doesn't grow when you paste a long paragraph.
- Create PROJECT-LOG.md, roadmap.md and how_we_work.md.

**Decided**
- Fix the input first, as one small reviewable change, and leave the wider redesign for the roadmap. Why: it's the bug you hit, and it's well scoped.
- Snippet text shows 3 lines with "Show more" instead of being cut at 2. Why: long entries couldn't be read at all.
- Seeded how_we_work.md only with rules visible from the repo and this session. The earlier rules you mention weren't available to me, so they still need adding.

**Shipped**
- Snippets screen (`Sources/RawiCore/UI/VocabularyView.swift`): stacked add card, expansion field that grows from 2 to 8 lines, filled Add button (⌘Return), expandable saved rows. Builds cleanly; not yet viewed in the running app; not committed.
- PROJECT-LOG.md, roadmap.md, how_we_work.md, docs/briefs/.

---

## 2026-11-18 — Working rules

**Asked**
- No pull requests (solo, no team). Replies short and non-technical, especially when a decision is needed. Prototype new features and design changes as a Claude Artifact first.

**Decided**
- Recorded all of it in how_we_work.md. Why: so it applies to every future session, not just this one.

**Shipped**
- how_we_work.md updated. Snippets fix pushed to origin.

---

## 2026-11-18 — Rest of the design critique

**Asked**
- Fix everything else from the critique. No prototype needed.

**Decided**
- Kept the screen names (Transforms, Commands, Destinations); only grouped the rail. Why: they are feature names used in the README.
- Undo only on Snippets and Dictionary for now. Why: their store could restore cleanly; the others need more work.
- Skipped a snippet usage count: nothing records usage yet.

**Shipped**
- Snippets: edit in place, search, hide sensitive text, hover-only delete with Undo.
- One growing field and button used on Dictionary, Snippets and Transforms.
- New Home screen (stats and last five dictations); rail grouped; Home opens first, shortcuts ⌘1–⌘9 follow rail order.
- Bigger click targets, brighter shortcut hints, labels on icon buttons.
- Menu panel: Recent open by default (last three), proper Quit button.
- All 868 tests pass. Not yet looked at in the running app.

---

## 2026-11-18 — Undo everywhere, snippet usage

**Asked**
- Finish the two leftovers (delete undo on the other screens, snippet usage count), then run the app.

**Decided**
- One shared Undo bar for the whole window, so every screen behaves the same.
- Restarted the installed Rawi on this branch's build to run it.

**Shipped**
- Undo after delete on Transforms, Commands, Destinations and History.
- Snippets show "used N times"; counted when a snippet fires in a dictation.
- 869 tests pass. Running build not visually checked by me.

---

## 2026-11-18 — Transforms and Commands match Snippets

**Asked**
- Same layout as Snippets on Transforms and Commands: add card on top, search, list below. Fix the "Add a command" design. Gap between the top three sidebar items and "Customize".

**Decided**
- Both screens use the shared add card, hover-only delete, and click-to-edit with Save/Cancel. "Try one" moved to the bottom as a stacked card.

**Shipped**
- Transforms and Commands rebuilt; 22pt-plus gap before "Customize" in the sidebar.
- Tests pass (one unrelated timing test flaked once, passed on rerun). New build is running.
