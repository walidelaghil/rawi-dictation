# Restore English words the engine spelled in Arabic script

## Problem
In mixed Arabic/English dictation, Whisper (Groq) and Deepgram Nova-3 both write English words in Arabic letters (ميتنغ, ديمو, نوشن, ريفيو). On the user's real mixed recording, 0 of 14 English words stayed in Latin on Deepgram and 1 of 14 on Whisper with no prompt. Prompting the engine does not fix it reliably (long primers made `whisper-large-v3` worse and caused the duplication regression). The polish prompt already says "English words stay in English letters", but the words have already left Latin script before polish sees them.

## Constraints
- Works for any user's accent and any engine; no word list, no per-dialect rules.
- Never translate, never drop a word. Arabic stays Arabic.
- Free-tier friendly: one short extra model call, low concurrency.

## Design
A new stage, `EnglishRestore`, after polish/cleanup and before `TermCorrector`, run on every dictation containing Arabic letters (decided with the user).

1. **Model call.** The Arabic cleanup model gets a narrow instruction: "Change only Arabic-script spellings of English words (loanwords) back into English letters. Change nothing else. Return the same text." Same word order, same punctuation.
2. **Token guard (`EnglishRestoreGuard`).** Split original and result into tokens. They must be the same count. Each pair must be identical, or an Arabic-script token replaced by a Latin-script token. Anything else (translation, dropped or added word, an Arabic word changed to another Arabic word, a Latin word changed) rejects the whole result and keeps the original text. Pure code, tested without a network.
3. **Failure handling.** Model error, timeout or rejection keeps the text as it was. The stage never blocks insertion beyond a short timeout.
4. **Config.** `cleanup.restoreEnglish` boolean, default on.

## Testing
- Guard unit tests first (red, then green): accepts Arabic-to-Latin swaps only; rejects translation, dropped words, count change, Arabic-to-Arabic edits, Latin-to-other edits.
- Pipeline test with a fake provider: restored text is used when the guard accepts, original kept when it rejects or the provider throws, stage skipped when there is no Arabic.
- Real-recording check (per CLAUDE.md): run the user's `mixed` recording through the pipeline and count Latin words kept (baseline 0-1 of 14); also run the Arabic and English recordings to confirm no regression. Eval spends Groq quota: low concurrency, retry on 429.
