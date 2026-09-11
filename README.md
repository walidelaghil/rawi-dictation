# Rawi

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
mkdir -p ~/Library/Application\ Support/Rawi/models
curl -L -o ~/Library/Application\ Support/Rawi/models/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
```

Build and install the app:

```bash
make install
```

That installs to `~/Applications/Rawi.app` — no admin password needed. Pass
`INSTALL_DIR=/Applications` if you would rather put it there (that one needs sudo).

Warm the Metal shader cache once. whisper.cpp compiles GPU shaders on its very
first run, which takes about 30 seconds — do it now so your first real dictation
isn't mistaken for a hang:

```bash
make warm
```

Launch it:

```bash
open ~/Applications/Rawi.app
```

A microphone icon appears in your menu bar. There is no Dock icon and no app
switcher entry — that is deliberate (`LSUIElement`).

---

## 2. Permissions you need to grant

Rawi needs three. macOS prompts for only one of them, so the other two must
be added by hand.

Run this at any time to see exactly where you stand:

```bash
~/Applications/Rawi.app/Contents/MacOS/Rawi --doctor
```

### Microphone — prompted automatically

**System Settings → Privacy & Security → Microphone**

Needed to record your voice. macOS asks the first time the app launches; just
allow it. Without it, nothing can be recorded.

### Input Monitoring — you must add this by hand

**System Settings → Privacy & Security → Input Monitoring** → press **+** → choose
`~/Applications/Rawi.app`

Needed for the keyboard event tap that watches for your hotkey and for `Esc`.
**Without it the hotkey does nothing at all** — no pill, no recording, no error.

> **This one is silently deceptive.** macOS lets the app *create* a listen-only
> event tap without this permission, and then simply never delivers any events. So
> a running app and a clean log are not proof that the hotkey works. `--doctor` is
> the reliable check.

### Accessibility — you must add this by hand

**System Settings → Privacy & Security → Accessibility** → press **+** → choose
`~/Applications/Rawi.app`

Needed to synthesize the ⌘V that pastes at your cursor. Without it, dictation
still works and the text still lands on your clipboard — the pill will say
`Copied — press ⌘V` — but nothing is pasted for you.

### What Rawi does *not* do with these

The event tap is created with `listenOnly`, which is a deliberate safety property,
not an optimisation: **the app never consumes a keystroke.** Every key you press —
`fn`, `Esc`, anything — continues to the app you are using, exactly as if
Rawi were not running. It also means that if this app ever hangs, it cannot
leave your keyboard unresponsive.

---

## 2a. If you can't grant permissions (managed / company Mac)

On a Mac managed by MDM (Jamf, Kandji, Intune…) you may not be in the `admin`
group. Privacy & Security then demands an administrator password you do not have,
and **no amount of retrying will work**. Check with:

```bash
id -Gn "$USER" | tr ' ' '\n' | grep -x admin || echo "not an admin"
```

Rawi still works. It detects this at launch and switches itself over —
you do not have to configure anything.

| Feature | Without any permission | Notes |
|---|---|---|
| Global hotkey | ✅ | Carbon `RegisterEventHotKey`, which predates TCC |
| Record, transcribe, clean | ✅ | Microphone is prompted normally, not admin-gated |
| Hands-free double-tap, 5-min auto-stop | ✅ | unchanged |
| Bare `fn` as the hotkey | ⚠️ | needs a combination instead — or Karabiner, below |
| Esc to cancel (passthrough) | ⚠️ | becomes `⌃⌥Esc`, which *is* consumed |
| **Auto-paste at the cursor** | ❌ | no workaround exists — see below |

### What you get instead

The hotkey becomes **`⌃⌥Space`** (configurable via `fallbackHotkey`), and cancel
becomes **`⌃⌥Esc`**. Hold to talk, double-tap for hands-free — all identical.

`⌥Space` is a good alternative if nothing else claims it — set `"hotkey":
"option+space"`. One trade-off: the Carbon backend *consumes* whatever it binds, and
`⌥Space` normally types a non-breaking space (U+00A0), so you lose that. Almost
nobody types one deliberately, but it is worth knowing if you work in typesetting.

The transcript is placed on your clipboard and the pill says `Copied — press ⌘V`.
**Press ⌘V to insert it.** That one keystroke is the entire cost.

### Why auto-paste genuinely cannot work

Pasting means synthesizing a ⌘V into another application, and every macOS API that
does so — `CGEventPost`, System Events via AppleScript, the Accessibility API —
requires the Accessibility permission by design. This is the security boundary that
stops arbitrary programs typing into your banking app, and there is no legitimate
way around it. Anything claiming otherwise is either asking for Accessibility under
another name or is malware. Clipboard + ⌘V is the honest answer.

### Getting the `fn` key back with Karabiner

If **Karabiner-Elements** is installed, your admin has almost certainly already
granted it Input Monitoring — that is the only way it can function. Karabiner can
run a shell command on key-down and key-up, so it can drive Rawi with the
real `fn` key using its permission rather than one you cannot get.

```bash
~/Applications/Rawi.app/Contents/MacOS/Rawi --install-karabiner-rule
```

That writes a rule file into Karabiner's assets folder. It **enables nothing** and
touches no existing configuration. Open **Karabiner-Elements → Complex
Modifications → Add rule** and enable whichever you want:

- *hold fn to dictate* — `fn` is re-sent first, so `fn`+arrows and the function row
  keep working
- *hold right-command to dictate* — if you would rather leave `fn` alone
- *Esc cancels dictation* — Esc still reaches your app; costs one process spawn per
  Esc press, so skip it if that bothers you

With the Karabiner route you can set `"hotkeyBackend": "carbon"` and simply not
press `⌃⌥Space`, or leave both active.

### Asking IT instead

If you would rather have the real thing, the request is specific and small: add
`~/Applications/Rawi.app` to **Accessibility** and **Input Monitoring**. In
Kandji that is a PPPC (Privacy Preferences Policy Control) profile. Bundle ID is
`com.welaghil.rawi`. Only Accessibility buys you anything you cannot
otherwise have — auto-paste.

---

## 3. Required macOS keyboard setting

**System Settings → Keyboard → "Press 🌐 fn key to" → `Do Nothing`**

Because Rawi only *listens* for `fn` rather than consuming it, macOS still
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
2. Name: `Rawi Dev` · Identity Type: **Self Signed Root** · Certificate
   Type: **Code Signing** → Create.
3. Build with it from then on:

```bash
make install SIGN_IDENTITY="Rawi Dev"
```

Grants now survive rebuilds. Put it in your shell profile if you like:
`export SIGN_IDENTITY="Rawi Dev"`.

---

## 5. Configuration

`~/.config/rawi/config.json`, created on first launch and re-read whenever
you save it — no restart needed. Open it from the menu bar with **Open Config
File…**.

Any key you leave out falls back to its default, so a three-line config is fine.
An *invalid* value is reported rather than silently ignored.

| Key | Default | What it does |
|---|---|---|
| `hotkey` | `"fn"` | `fn`, `rightOption`, `rightCommand`, `rightControl`, `rightShift`, or a combo like `cmd+shift+d` |
| `hotkeyBackend` | `"auto"` | `auto`, `eventTap` (needs Input Monitoring, supports bare `fn`), `carbon` (no permission, needs a combo) |
| `fallbackHotkey` | `"ctrl+option+space"` | Used when the Carbon backend is active and `hotkey` is a bare modifier |
| `cancelHotkey` | `"ctrl+option+escape"` | Cancel key in Carbon mode. Consumed, unlike Esc in event-tap mode |
| `maxPushToTalkSeconds` | `120` | Safety stop if a Carbon key-release event is missed |
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

API keys never go in this file. They live in `~/.config/rawi/.env` — see
[`.env.example`](.env.example).

[`config.example.json`](config.example.json) is a known-good configuration, verified
working on a managed Mac with **neither Accessibility nor Input Monitoring granted**:
`⌥Space` push-to-talk via the permission-free Carbon backend, local whisper.cpp, and
local Ollama cleanup. Copy it to `~/.config/rawi/config.json` to start from
there.

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

On first launch Rawi picks one based on what it finds: an `OPENAI_API_KEY`
in `.env`, else an `ANTHROPIC_API_KEY`, else a running Ollama, else `off`.

| Provider | Cost | Latency | Works offline |
|---|---|---|---|
| `ollama` (`qwen2.5:1.5b`) | free | **0.8–1.3 s measured** | ✅ |
| `openai` (`gpt-4o-mini`) | ~$0.30/mo at 100 dictations/day | ~0.5 s | ❌ |
| `anthropic` (Haiku) | ~$2/mo at the same rate | ~0.7 s | ❌ |
| `off` | free | none | ✅ |

End-to-end on an M4, local throughout: ~0.6 s transcription + ~0.8–1.3 s cleanup,
so roughly **1.5–2 seconds** from releasing the key to text appearing.

> **A ChatGPT or Claude subscription does not include API access.** ChatGPT
> Plus/Go and Claude Pro/Max are consumer chat products; the OpenAI and Anthropic
> APIs are billed separately, with their own keys and their own prepaid balance.
> Nothing this app sends to those APIs draws on a subscription.

For a free, fully offline setup:

```bash
brew install ollama
brew services start ollama
ollama pull qwen2.5:1.5b
```

then set `"cleanup": { "provider": "ollama", "model": "qwen2.5:1.5b" }`.

### Why the 1.5b and not something bigger

Counter-intuitively, bigger was worse here. Benchmarked on real whisper output:

| Model | Latency | Behaviour |
|---|---|---|
| `qwen2.5:1.5b` | 0.8–1.3 s | faithful — removes fillers, changes nothing else |
| `qwen2.5:3b` | 1.4–2.0 s | **rewrites**: dropped "we need to do three things", reworded "by end of day" |
| `gemma3:4b` | ~2.0 s | left some fillers in, slower |

A larger model is "smart" enough to want to *improve* your dictation, which is
exactly wrong — you want your words, not its edit of them. Smaller and dumber is
the right tool for this job.

### The safety net

Cleanup output is validated before it is typed. A local model will sometimes
answer or obey your dictation rather than clean it — dictating *"what is the
capital of France"* can come back as *"Paris"*. `CleanupGuard` checks that enough
of your actual words survived; if not, the raw transcript is inserted instead and
the reason is logged. The prompt is the first line of defence and the guard is the
second, because no wording makes a 1.5B model reliable on its own.

If you edit `cleanup.prompt`, keep the `<transcript>` framing — it is what stops
the model treating your dictation as instructions addressed to it.

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
Run `make doctor`. If it says the Carbon backend is active, the key is
`⌃⌥Space`, not `fn` — see §2a. Otherwise it is almost always missing Input Monitoring. Remember that a running
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
macOS disables an event tap that responds too slowly. Rawi watches for this
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

**I get a single odd word like "You" instead of what I said.**
That is whisper hallucinating from silence. The log records the peak input level
after every recording — `peak level 0.001` means nothing was captured. Check
System Settings → Sound → Input: the right device selected, input volume up, and
the mic's own hardware mute switch off.

**Nothing gets transcribed but I definitely spoke.**
Check the log at `~/Library/Logs/Rawi/rawi.log`. On a transcription
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

Logs: `~/Library/Logs/Rawi/rawi.log` (rotates at 5 MB).

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
- Recordings live in `~/Library/Application Support/Rawi/recordings/` and
  are deleted as soon as the text is inserted. They are kept only when
  transcription fails, so you do not lose a dictation to a crash — the log tells
  you where.
