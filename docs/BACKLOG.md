# Rawi — backlog

Deferred work, with the reasoning that deferred it. Anything here was considered
and consciously left out, not forgotten.

---

## Commands — speech to action

**Status:** designed, deferred out of v2. Hidden — no menu item, no nav entry, no
config key.

**What it is.** Spoken phrases that trigger an action instead of producing text:
*"run my standup"*, *"log this as a bet"*, *"open a doc about our marketing
strategy"*. A local, deterministic phrase match — never an LLM inferring intent —
followed by a confirmation showing the exact action and its arguments, and only
then execution. Designed in full on the canvas: see the **Commands** artboard and
the **Speaking a command** flow.

**Why it is deferred rather than dropped.**

1. **Lemon built this and walked away from it.** They pivoted to voice-to-prompt,
   which is the same insight from the other end: don't execute the action, produce
   the input to the thing that executes it. A company abandoning a feature is the
   most useful evidence available about it.
2. **The confirmation tax.** A command you did not mean is far worse than a
   sentence you did not mean, so it needs a confirm step — and the confirm step
   destroys the speed that justified using voice.
3. **Intent is genuinely ambiguous.** *"log this as a bet"* is indistinguishable
   from dictating the words "log this as a bet".
4. **The surface is unbounded.** Every user wants a different five commands, so
   you end up building a framework rather than a feature.

**What is already possible if it is picked up.** Verified on this machine, no
administrator needed: opening URLs, running local scripts, calling APIs with keys
from `.env`, and driving other apps through Automation (AppleScript reached Finder
and Chrome without a TCC denial). None of it needs the Accessibility or Input
Monitoring grants this Mac cannot be given.

**If it is built.** Ship five commands actually in use, not a framework. The
phrase list is authored by hand; matching stays local and deterministic;
confirmation is mandatory and shows arguments verbatim.

**The nearest safe substitute, already in v2 scope.** *Turn this into a prompt*
under Transforms — the feature Lemon pivoted toward, and the one part of this that
carries no execution risk.

---

## Smaller deferrals

- ~~**Field-level destination awareness**~~ — shipped (2026-09-15). A rule can name
  a field by its label, placeholder or identifier; Jira's summary and description
  and an email subject ship as built-ins, and "Detect field" fills a new rule from
  the field you click into.
- ~~**Auto-paste**~~ — shipped once Accessibility was granted (2026-09-15). Rawi
  pastes only when a text field has focus, and copies with a ⌘V hint otherwise.
- ~~**Learn from corrections**~~ — shipped (2026-09-15). After a paste, Rawi reads
  back the stretch it typed and learns a spelling you fix, the way Wispr Flow's
  dictionary fills itself. Learning beyond single-word spelling (rephrasings,
  style) is still out of scope.
- **Streaming partial transcription** — large engineering lift; at ~2s round trip
  it solves a wait that is not really there.
