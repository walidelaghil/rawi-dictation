# How we work

Rules for working on Rawi. Add a rule when we agree one; keep each to a line plus the reason.

## Files we keep
- **PROJECT-LOG.md** — append only. Before a session ends and after every merge: what was asked, decided and why, shipped. Never edit old entries.
- **roadmap.md** — headings are columns, bullets are cards, `[[brief]]` links open `docs/briefs/`. When told "add this to roadmap": add it, confirm it was added, and share roadmap.md.
- **how_we_work.md** — this file.

## Rules
- Solo project, no reviewers: **no pull requests**. Commit and push straight to the branch.
- The owner is not technical. Keep replies short and plain; no jargon.
- Decisions: ask one short question with 2–3 options and a recommendation. No long write-ups before a choice.
- New features and anything that changes the design: **prototype first as a Claude Artifact**, get a yes, then build it.
- Work in a git worktree; never `cd` out of it.
- No bare `git stash`; use a WIP commit instead (the stash is shared between sessions).
- Commit and push only when asked.
- Ask before anything outward-facing or hard to reverse.
- Report outcomes honestly: say what was built, what was verified, and what wasn't.
- Keep UI inside the design tokens (`TypeScale`, `Radius`, `RawiColors`); no hardcoded sizes, radii or colours, no `.opacity()` on text tokens.
- Benchmark for desktop UI/UX is Wispr Flow.

## To add
The rules you said we'd already agreed earlier aren't in this session's context. Paste them here or tell me and I'll add them.
