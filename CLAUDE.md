# How we work on Rawi

## Use superpowers in every session

Start every session by loading `superpowers:using-superpowers`, and invoke the matching skill before any response or action, including clarifying questions. If a skill might apply, use it.

| Task | Skill first |
|---|---|
| Any bug, wrong output, failing test | `superpowers:systematic-debugging` |
| New feature or behaviour change | `superpowers:brainstorming`, then `superpowers:test-driven-development` |
| Multi-step change | `superpowers:writing-plans` |
| Before saying "done", "fixed" or "installed" | `superpowers:verification-before-completion` |

## Rules that came from real failures

- **Test first.** Write the failing test, watch it fail, then fix. The mixed-speech release that made short dictations come out twice skipped this.
- **Real recordings beat synthetic ones.** The Arabic eval corpus is text-to-speech. Before shipping anything that changes transcription, run it on real recordings or the real History too, because synthetic speech missed the duplication bug.
- **Check History before guessing.** Compare dictations from before and after a change instead of arguing from theory.
- **Keep Arabic as Arabic.** Never translate, never drop a language. Mixed Arabic and English must stay in the script it was spoken in.
- **Mind Groq's free tier.** Evals spend the user's quota. Keep concurrency low and retry on 429.
