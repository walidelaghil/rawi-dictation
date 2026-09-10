# WhisperFlow

System-wide AI dictation for macOS. Hold a key, speak, release — cleaned-up text
appears at your cursor in whatever app you are using.

A local-first alternative to Wispr Flow. No account, no sign-in, no telemetry, no
network calls at all unless you explicitly configure a hosted provider.

- **Hold `fn`** → record. Release → transcribe, clean up, paste at the cursor.
- **Double-tap `fn`** → hands-free session, nothing held. One more tap ends it.
  Auto-stops after 5 minutes so a forgotten session cannot record all afternoon.
- **`Esc`** → cancel. Drops the recording, or kills a transcription already running.
  Esc is *never* swallowed, so it still reaches the app you are typing in.
- Transcribes with **whisper.cpp locally**, or the **Groq / OpenAI** Whisper API.
- Optionally pipes the transcript through an **LLM** to strip filler words, fix
  punctuation, and match casing to dictation style.
- Leaves the transcript on your clipboard so you can paste it again.
- Tiny floating pill while recording, showing the mode and a live level meter.
- Menu bar toggle, launch at login, and a plain JSON settings file.

---

## 1. Install

```bash
brew install whisper-cpp
```

Download a model (`small.en` is the sweet spot — ~465 MB, ~0.6 s per dictation on
an M-series Mac; `base.en` is ~150 MB and nearly as good for clear speech):

```bash
mkdir -p ~/Library/Application\ Support/WhisperFlow/models
curl -L -o ~/Library/Application\ Support/WhisperFlow/models/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
```

Build and install the app:

```bash
make install
```

That installs to `~/Applications/WhisperFlow.app` — no admin password needed. Pass
`INSTALL_DIR=/Applications` if you would rather put it there (that one needs sudo).

Warm the Metal shader cache once. whisper.cpp compiles GPU shaders on its very
first run, which takes about 30 seconds — do it now so your first real dictation
isn't mistaken for a hang:

```bash
make warm
```

Launch it:

```bash
open ~/Applications/WhisperFlow.app
```

A microphone icon appears in your menu bar. There is no Dock icon and no app
switcher entry — that is deliberate (`LSUIElement`).

---

## 2. Permissions you need to grant

WhisperFlow needs three. macOS prompts for only one of them, so the other two must
be added by hand.

Run this at any time to see exactly where you stand:

```bash
~/Applications/WhisperFlow.app/Contents/MacOS/WhisperFlow --doctor
```

### Microphone — prompted automatically

**System Settings → Privacy & Security → Microphone**

Needed to record your voice. macOS asks the first time the app launches; just
allow it. Without it, nothing can be recorded.

### Input Monitoring — you must add this by hand

**System Settings → Privacy & Security → Input Monitoring** → press **+** → choose
`~/Applications/WhisperFlow.app`

Needed for the keyboard event tap that watches for your hotkey and for `Esc`.
**Without it the hotkey does nothing at all** — no pill, no recording, no error.

> **This one is silently deceptive.** macOS lets the app *create* a listen-only
> event tap without this permission, and then simply never delivers any events. So
> a running app and a clean log are not proof that the hotkey works. `--doctor` is
> the reliable check.

### Accessibility — you must add this by hand

**System Settings → Privacy & Security → Accessibility** → press **+** → choose
`~/Applications/WhisperFlow.app`

Needed to synthesize the ⌘V that pastes at your cursor. Without it, dictation
still works and the text still lands on your clipboard — the pill will say
`Copied — press ⌘V` — but nothing is pasted for you.

### What WhisperFlow does *not* do with these

The event tap is created with `listenOnly`, which is a deliberate safety property,
not an optimisation: **the app never consumes a keystroke.** Every key you press —
`fn`, `Esc`, anything — continues to the app you are using, exactly as if
WhisperFlow were not running. It also means that if this app ever hangs, it cannot
leave your keyboard unresponsive.

---

## 3. Required macOS keyboard setting

**System Settings → Keyboard → "Press 🌐 fn key to" → `Do Nothing`**

Because WhisperFlow only *listens* for `fn` rather than consuming it, macOS still
applies its own `fn` behaviour on top. Left at the default, pressing `fn` will
also open the emoji picker or start Apple's own dictation. Setting it to
`Do Nothing` fixes that.

Prefer not to change it? Set `"hotkey": "rightOption"` in your config instead —
right-Option conflicts with nothing and needs no system change.

---

## 4. Keeping permissions across rebuilds

TCC permission grants are bound to an app's **code signature**. The default
ad-hoc signature (`-`) changes on every build, so each `make install` looks like a
brand-new app and you have to re-grant Accessibility and Input Monitoring.

Fix it once with a self-signed certificate:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant →
   Create a Certificate…**
2. Name: `WhisperFlow Dev` · Identity Type: **Self Signed Root** · Certificate
   Type: **Code Signing** → Create.
3. Build with it from then on:

```bash
make install SIGN_IDENTITY="WhisperFlow Dev"
```

Grants now survive rebuilds. Put it in your shell profile if you like:
`export SIGN_IDENTITY="WhisperFlow Dev"`.

---

## 5. Configuration

`~/.config/whisperflow/config.json`, created on first launch and re-read whenever
you save it — no restart needed. Open it from the menu bar with **Open Config
File…**.

Any key you leave out falls back to its default, so a three-line config is fine.
An *invalid* value is reported rather than silently ignored.

| Key | Default | What it does |
|---|---|---|
| `hotkey` | `"fn"` | `fn`, `rightOption`, `rightCommand`, `rightControl`, `rightShift`, or a combo like `cmd+shift+d` |
| `doubleTapWindowMs` | `350` | How long after the first press a second tap still counts as a double-tap |
| `minHoldMs` | `250` | Holds shorter than this are treated as taps, not speech |
| `maxSessionSeconds` | `300` | Hands-free auto-stop. 5 minutes |
| `engine` | `"whispercpp"` | `whispercpp` (local, offline), `groq`, or `openai` |
| `whispercpp.binary` | `"whisper-cli"` | Name on `PATH`, or an absolute path |
| `whispercpp.model` | `…/models/ggml-small.en.bin` | Path to a `ggml-*.bin` model |
| `whispercpp.language` | `"en"` | Or `"auto"` to detect |
| `whispercpp.threads` | `8` | CPU threads |
| `api.groqModel` | `"whisper-large-v3-turbo"` | Model for `engine: groq` |
| `api.openaiModel` | `"whisper-1"` | Model for `engine: openai` |
| `cleanup.provider` | detected | `openai`, `anthropic`, `ollama`, or `off` |
| `cleanup.model` | per provider | e.g. `gpt-4o-mini`, `qwen2.5:3b` |
| `cleanup.prompt` | see below | The cleanup instruction. Edit freely |
| `output.restorePreviousClipboard` | `false` | Restore your previous clipboard after pasting |
| `output.restoreDelayMs` | `300` | How long to wait before restoring |

API keys never go in this file. They live in `~/.config/whisperflow/.env` — see
[`.env.example`](.env.example).

### The cleanup prompt

The default instructs the model to remove filler words and false starts, fix
punctuation and sentence boundaries, apply sentence casing, capitalise proper
nouns, and change nothing else. It is plain text in your config — reword it to
taste. Set `cleanup.provider` to `off` to skip this stage entirely and paste
whisper's raw output.

### Clipboard behaviour

By default the transcript stays on your clipboard, so ⌘V pastes it again.

Setting `restorePreviousClipboard: true` puts your previous clipboard back
afterwards. **This is inherently racy** and off by default for that reason:
`restoreDelayMs` is a guess at how long the target app takes to read the
pasteboard, and a slow app can end up pasting nothing. Raise the delay if you hit
this, or leave the feature off.

---

## 6. Choosing a cleanup provider

On first launch WhisperFlow picks one based on what it finds: an `OPENAI_API_KEY`
in `.env`, else an `ANTHROPIC_API_KEY`, else a running Ollama, else `off`.

| Provider | Cost | Latency | Works offline |
|---|---|---|---|
| `ollama` (local 1.5–3B) | free | ~1–2 s | ✅ |
| `openai` (`gpt-4o-mini`) | ~$0.30/mo at 100 dictations/day | ~0.5 s | ❌ |
| `anthropic` (Haiku) | ~$2/mo at the same rate | ~0.7 s | ❌ |
| `off` | free | none | ✅ |

> **A ChatGPT or Claude subscription does not include API access.** ChatGPT
> Plus/Go and Claude Pro/Max are consumer chat products; the OpenAI and Anthropic
> APIs are billed separately, with their own keys and their own prepaid balance.
> Nothing this app sends to those APIs draws on a subscription.

For a free, fully offline setup:

```bash
brew install ollama
ollama serve          # or: brew services start ollama
ollama pull qwen2.5:3b
```

then set `"cleanup": { "provider": "ollama", "model": "qwen2.5:3b" }`.

---

## 7. Manual verification checklist

The permission-gated paths — the event tap, the synthetic ⌘V, and the pill's focus
behaviour — cannot be meaningfully tested without live TCC grants and a real
microphone, so they are verified by hand rather than with fabricated coverage.
Everything else is covered by `swift test` (111 tests).

Work through these once after granting permissions:

- [ ] Hold `fn` in TextEdit, speak, release → cleaned text appears at the cursor
- [ ] The pill appears while recording and its level meter moves as you speak
- [ ] Focus never leaves TextEdit while the pill is up (the caret keeps blinking)
- [ ] Double-tap `fn` → pill reads **Hands-free**; a single tap ends it and inserts
- [ ] A hands-free session left alone auto-stops at 5 minutes
- [ ] `Esc` during recording discards it — nothing is pasted
- [ ] `Esc` during transcription aborts it — `pgrep whisper-cli` returns nothing
- [ ] `Esc` still dismisses a Safari dialog while the app runs (proves listen-only)
- [ ] The transcript is still on the clipboard afterwards; ⌘V pastes it again
- [ ] With `restorePreviousClipboard: true`, your previous clipboard comes back
- [ ] Menu bar → **Enabled** off → the hotkey does nothing
- [ ] **Launch at Login** on → the icon returns after a reboot
- [ ] Turn Wi-Fi off with `engine: whispercpp` and `cleanup.provider: ollama` or
      `off` → dictation still works

---

## 8. Troubleshooting

**The hotkey does nothing.**
Run `--doctor`. Almost always missing Input Monitoring. Remember that a running
app and a clean log prove nothing here — macOS creates the tap and then delivers
no events. If it is granted and still dead, remove the app from the Input
Monitoring list with **−**, re-add it, and relaunch.

**Text is transcribed but not pasted.**
Accessibility is not granted. The pill says `Copied — press ⌘V` and the text is on
your clipboard.

**`fn` also opens the emoji picker or Apple's dictation.**
Section 3 — set "Press fn key to" to `Do Nothing`.

**Permissions disappear after every rebuild.**
Section 4 — sign with a stable self-signed identity.

**The hotkey works, then stops after a long transcription.**
macOS disables an event tap that responds too slowly. WhisperFlow watches for this
and re-arms itself, so this should self-heal within a keystroke. If it persists,
check the log.

**`whisper-cli` not found.**
`brew install whisper-cpp`, or set `whispercpp.binary` to an absolute path.

**The first dictation takes ~30 seconds.**
whisper.cpp is compiling Metal shaders. One time only. `make warm`.

**Cleanup is being skipped.**
Check `--doctor`. Either the key is missing from `.env`, or Ollama is not running.
Cleanup failure is deliberately non-fatal — the raw transcript is inserted rather
than losing your dictation — so this shows up as unpolished text, not an error.

**Nothing gets transcribed but I definitely spoke.**
Check the log at `~/Library/Logs/WhisperFlow/whisperflow.log`. On a transcription
failure the WAV is kept and its path logged, so you can play it back and confirm
whether audio was actually captured.

---

## 9. Development

```bash
make test        # 111 tests
make run         # run from build/ with verbose logging to stderr
make bundle      # build the .app without installing
make doctor      # print permission and provider status
make uninstall   # remove the app, keep config and models
```

Logs: `~/Library/Logs/WhisperFlow/whisperflow.log` (rotates at 5 MB).

Architecture: a `DictationController` state machine drives
`AudioRecorder → TranscriptionEngine → CleanupProvider → TextInserter`, each behind
a protocol so it is swappable and testable with fakes. Design notes are in
[`docs/superpowers/specs/`](docs/superpowers/specs/) and the build plan in
[`docs/superpowers/plans/`](docs/superpowers/plans/).

## 10. Privacy

- No account, no sign-in, no telemetry, no analytics, no crash reporting.
- With `engine: whispercpp` and `cleanup.provider` of `ollama` or `off`, **nothing
  leaves your machine.**
- With a hosted provider configured, audio (or the transcript) goes only to that
  provider's API. Nowhere else.
- API keys are read from `.env`, held in memory, and never logged or written back
  to disk.
- Recordings live in `~/Library/Application Support/WhisperFlow/recordings/` and
  are deleted as soon as the text is inserted. They are kept only when
  transcription fails, so you do not lose a dictation to a crash — the log tells
  you where.
