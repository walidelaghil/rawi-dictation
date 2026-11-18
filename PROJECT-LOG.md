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
