# WhisperFlow — System-Wide AI Dictation for macOS

**Date:** 2026-09-09
**Status:** Approved
**Target:** macOS 26.x, Apple Silicon, Swift 6.3

## 1. Purpose

A background macOS app that turns held-key speech into cleaned-up text inserted at the
cursor of whatever app has focus. A local-first alternative to Wispr Flow: no accounts,
no telemetry, fully functional offline when using the local Whisper model.

Single-user personal tool. No authentication, no multi-user concerns, no sync.

## 2. Success Criteria

1. Holding `fn` records; releasing it inserts cleaned text at the cursor in any app.
2. Double-tapping `fn` starts a hands-free session; one more tap ends it.
3. A hands-free session auto-stops after 5 minutes.
4. `Esc` cancels a recording or an in-flight transcription, and still reaches the
   focused app.
5. Works with no network when `engine: whispercpp` and `cleanup.provider: ollama|off`.
6. No account, no network calls other than the explicitly configured provider APIs.

## 3. Stack Decision

Native Swift 6 + AppKit, built with SwiftPM, bundled as `WhisperFlow.app` with
`LSUIElement = true`.

Rationale: every hard requirement maps to an AppKit/CoreGraphics API — `CGEventTap`
for fn monitoring, `NSPanel` for a non-focus-stealing overlay, `CGEvent` for synthetic
Cmd-V, `SMAppService` for login items. TCC permission grants (Accessibility, Input
Monitoring, Microphone) are bound to a signed `.app` bundle, so a bare script or
binary is not viable.

Rejected: Python (no clean fn-key or non-activating-panel story), Electron (bundle
size, no privileged input access).

## 4. Architecture

```
HotkeyMonitor ──► DictationController ──► AudioRecorder
                        │                      │
                        │                      ▼
                        │              TranscriptionEngine
                        │                      │
                        │                      ▼
                        │               CleanupProvider
                        │                      │
                        │                      ▼
                        │                 TextInserter
                        │
                        ├──► PillWindow      (observes state)
                        └──► MenuBarController (observes state)
```

`DictationController` is the only component that knows the whole flow. Each stage sits
behind a protocol so engines and providers are swappable and unit-testable in isolation.

### State machine

```
idle
 ├─ press ──────────────► recording(pushToTalk)
 ├─ doubleTap ──────────► recording(handsFree)
recording(pushToTalk)
 ├─ release (>250ms) ───► transcribing
 ├─ release (<250ms) ───► pendingDoubleTap
 └─ esc ────────────────► idle (audio discarded)
pendingDoubleTap
 ├─ press within 350ms ─► recording(handsFree)
 └─ timeout ────────────► idle (discarded, too short for speech)
recording(handsFree)
 ├─ tap ────────────────► transcribing
 ├─ 5min elapsed ───────► transcribing
 └─ esc ────────────────► idle (audio discarded)
transcribing ─► cleaning ─► inserting ─► idle
 (esc at any of these three ─► idle, work cancelled)
```

## 5. Components

### 5.1 Input — `Input/`

A single **listen-only** `CGEventTap` at `.cgSessionEventTap` handles all key input.

Listen-only is deliberate: the app never consumes a keystroke. `Esc` therefore reaches
the focused app for free, and an app hang can never leave the keyboard unresponsive.

- `HotkeyMonitor` — owns the tap, its run-loop source, and re-arming on
  `.tapDisabledByTimeout` / `.tapDisabledByUserInput`.
- `HotkeyConfig` — parses the configured hotkey string into either a modifier-flag
  match (`fn`, `rightOption`) or a keycode + modifier mask.
- `TapPattern` — pure logic resolving press/release timestamps into
  `.hold`, `.doubleTap`, or `.tooShort`. No AppKit dependency, fully unit-tested.

`fn` is observed via `.flagsChanged` events carrying `.maskSecondaryFn`.
`Esc` is keycode 53, matched on `.keyDown`, and dispatched to the controller only when
state is not `idle`.

**Accepted limitation:** because the tap is listen-only, macOS still applies its own fn
behaviour. Setup requires System Settings → Keyboard → "Press fn key to" → *Do Nothing*.

### 5.2 Audio — `Audio/`

- `AudioRecorder` — `AVAudioEngine` input-node tap. Hardware format (typically 48 kHz)
  is converted via `AVAudioConverter` to the 16 kHz mono Int16 that Whisper requires,
  and streamed to a temp WAV rather than buffered wholly in memory.
  Publishes a smoothed RMS level for the pill's meter.
- `WAVWriter` — incremental RIFF/WAVE writer; header lengths patched on close.

Recordings live in `~/Library/Application Support/WhisperFlow/recordings/` and are
deleted on successful insertion.

### 5.3 Transcription — `Transcribe/`

```swift
protocol TranscriptionEngine {
    func transcribe(wav: URL) async throws -> String
    func cancel()
}
```

- `WhisperCppEngine` — spawns `whisper-cli -m <model> -f <wav> -nt -np`, reads stdout.
  Cancellation terminates the process. Model path and binary path come from config;
  binary is located via config, then `PATH`, then Homebrew's default prefix.
- `WhisperAPIEngine` — multipart POST to Groq
  (`api.groq.com/openai/v1/audio/transcriptions`, `whisper-large-v3-turbo`) or OpenAI
  (`api.openai.com/v1/audio/transcriptions`, `whisper-1`). Cancellation via
  `URLSessionTask.cancel()`.

Selected by the `engine` config key: `whispercpp` | `groq` | `openai`.

### 5.4 Cleanup — `Cleanup/`

```swift
protocol CleanupProvider {
    func clean(_ transcript: String) async throws -> String
    func cancel()
}
```

Implementations: `OpenAICleanup`, `AnthropicCleanup`, `OllamaCleanup`, `NoopCleanup`.
Chosen by `cleanup.provider`: `openai` | `anthropic` | `ollama` | `off`.

The system prompt lives in config as editable text, not compiled in. Default instructs:
remove filler words, fix punctuation and sentence boundaries, match casing to dictation
style, change nothing else, return only the corrected text.

Cleanup failure is non-fatal — on error the raw transcript is inserted and the failure
is logged and flashed on the pill. Dictation must never be lost to a cleanup problem.

### 5.5 First-run setup — `Config/FirstRunSetup.swift`

On first launch, with no config present:

1. Read `.env` for `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GROQ_API_KEY`.
2. Probe `http://localhost:11434/api/tags` for a live Ollama.
3. Probe for `whisper-cli` and a model file.
4. Write `config.json` with the detected choices active and every alternative present
   as a sibling `_comment` key, so switching provider is a one-line hand edit.

Detection order for cleanup: explicit `.env` key → Ollama → `off`.

### 5.6 Output — `Output/`

- `PasteboardStash` — snapshots all types on the general pasteboard and restores them.
- `TextInserter` — writes the text, then synthesizes Cmd-V as
  `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with `.maskCommand`, posted to
  `.cghidEventTap`.

Default behaviour leaves the transcript on the clipboard for re-pasting.
`output.restorePreviousClipboard: true` restores the prior contents after 300 ms.

**Known limitation, documented in README:** clipboard restore is inherently racy. The
delay is a heuristic for how long the target app takes to read the pasteboard; a slow
app can lose the paste. Off by default for this reason.

### 5.7 UI — `UI/`

- `PillWindow` — `NSPanel`, `.nonactivatingPanel`, `canBecomeKey = false`,
  `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`,
  positioned bottom-centre of the active screen.
  `canBecomeKey = false` is load-bearing: a panel that took focus would redirect the
  paste away from the intended app.
- `PillView` — SwiftUI in an `NSHostingView`. Shows mode (push-to-talk / hands-free),
  live level meter, elapsed time, and current stage. Hands-free shows a countdown once
  under 60 s remain.
- `MenuBarController` — `NSStatusItem`. Menu: Enabled toggle, current mode, Launch at
  Login (`SMAppService.mainApp`), Reveal Config, Permission status, Logs, Quit.

### 5.8 Config — `Config/`

`~/.config/whisperflow/config.json`, with a sibling `.env`. Watched via `DispatchSource`
and hot-reloaded on change.

```json
{
  "hotkey": "fn",
  "doubleTapWindowMs": 350,
  "minHoldMs": 250,
  "maxSessionSeconds": 300,
  "engine": "whispercpp",
  "whispercpp": { "binary": "whisper-cli", "model": "~/.../ggml-small.en.bin" },
  "cleanup": { "provider": "ollama", "model": "qwen2.5:3b", "prompt": "..." },
  "output": { "restorePreviousClipboard": false }
}
```

### 5.9 Permissions — `System/Permissions.swift`

Checks and surfaces: Accessibility (`AXIsProcessTrusted`), Input Monitoring
(`IOHIDCheckAccess`), Microphone (`AVCaptureDevice.authorizationStatus`).
Menu bar shows a warning badge while any is missing, with a menu item deep-linking to
the relevant System Settings pane.

## 6. Error Handling

| Failure | Behaviour |
|---|---|
| Mic permission denied | Pill shows error, menu badge, deep link to Settings |
| Event tap creation fails | Menu badge; app runs but hotkey inert |
| Event tap disabled by timeout | Auto re-armed, logged |
| `whisper-cli` missing / non-zero exit | Error on pill, **WAV retained**, path logged |
| Transcription API error | Error on pill, **WAV retained**, path logged |
| Cleanup fails | Raw transcript inserted anyway, failure logged |
| Accessibility denied at paste | Text left on clipboard, pill says "copied — paste manually" |
| Empty transcript | Silently return to idle |

Audio is never silently discarded on a downstream failure.
Logs: `~/Library/Logs/WhisperFlow/whisperflow.log`, rotated at 5 MB.

## 7. Testing

Automated (`swift test`) covers pure logic:
- `TapPattern` — hold vs double-tap vs too-short across timing boundaries
- State machine transitions, including every Esc path and the 5-minute auto-stop
- Config and `.env` parsing, defaults, malformed input
- Cleanup prompt construction and response unwrapping per provider
- `WAVWriter` header framing and sample-rate conversion arithmetic
- Provider detection logic in `FirstRunSetup`, with injected probes

Permission-gated paths (event tap, synthetic paste, panel focus behaviour) get a
written manual verification checklist in the README rather than fabricated coverage —
they cannot run meaningfully in CI or without TCC grants.

## 8. Build and Install

`make build` → `swift build -c release` → assemble bundle → codesign → `make install`
copies to `/Applications/WhisperFlow.app`.

**Code signing:** TCC grants bind to the code signature. Ad-hoc signatures change on
every rebuild, forcing re-grant of Accessibility and Input Monitoring each time. The
README documents creating a one-time self-signed certificate in Keychain Access and
setting `SIGN_IDENTITY` so grants persist across rebuilds.

## 9. File Layout

```
Package.swift
Makefile
Sources/WhisperFlow/
  main.swift
  App/{AppDelegate,DictationController}.swift
  Input/{HotkeyMonitor,HotkeyConfig,TapPattern}.swift
  Audio/{AudioRecorder,WAVWriter}.swift
  Transcribe/{TranscriptionEngine,WhisperCppEngine,WhisperAPIEngine}.swift
  Cleanup/{CleanupProvider,OpenAICleanup,AnthropicCleanup,OllamaCleanup}.swift
  Output/{TextInserter,PasteboardStash}.swift
  UI/{PillWindow,PillView,MenuBarController}.swift
  Config/{Config,DotEnv,FirstRunSetup,ConfigWatcher}.swift
  System/{Permissions,Logger}.swift
Tests/WhisperFlowTests/
Resources/Info.plist
README.md
```

## 10. Explicitly Out of Scope

- Graphical settings window (config is a hand-edited JSON file)
- Custom vocabulary / dictionary
- Per-app dictation profiles
- Streaming/partial transcription during recording
- Any telemetry, analytics, crash reporting, or account system
- Windows or Linux support
