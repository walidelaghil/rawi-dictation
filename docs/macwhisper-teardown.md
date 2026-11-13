# Why MacWhisper feels fast and Rawi didn't

A static look at MacWhisper 15.4 (build 1540, `com.goodsnooze.MacWhisper`), taken
from the shipped bundle, plus measurements of Rawi on the same machine (M4, 16 GB).

## What MacWhisper ships

How each finding is known: *bundle listing* or *strings* means it came from the
shipped files; *inferred* means it is a reading of names, not observed at runtime.

| Finding | Evidence |
|---|---|
| Two local engines: Argmax's SDK (WhisperKit Pro and Parakeet on Core ML / Neural Engine) and whisper.cpp | `Contents/Frameworks/ArgmaxSDK.framework`, `ArgmaxOSSDynamic.framework`, `whisper.framework` (bundle listing) |
| Transcribes while you speak, with text split into confirmed and still-changing parts | ArgmaxSDK strings `StreamingTranscriber`, `TranscriptionStreamSession`, `forwardStreamingStep`, and a field mangled as `confirmed` / `hypo` / `flushed` (strings) |
| Keeps the dictation model loaded instead of loading it per use | main binary strings `dictationShouldLoadModelOnLaunch`, "Previous dictation is winding down while its model loads" (strings) |
| Parakeet is the fast path; it supports custom vocabulary, Whisper does not there | ArgmaxSDK: "Custom vocabulary can only be enabled for Parakeet Models" (strings) |
| Cloud is a first-class option, not a fallback | hosts in main binary: `api.groq.com/openai/v1`, `api.openai.com`, `api.elevenlabs.io`, `api.assemblyai.com`, `api.gladia.io`, `api.mistral.ai/v1/audio/transcriptions`, `api.cartesia.ai/stt`, `api.x.ai/v1/stt`, Deepgram, Speechmatics (strings) |
| Whisper model list served remotely | `https://cdn.macwhisper.com/models.json`: tiny through large-v3 plus turbo, with turbo marked as the recommended one |

Parakeet v3 covers European languages only. For Arabic, MacWhisper is in the same
position as Rawi: Whisper turbo locally, or a cloud provider. So the speed
difference is not a better model. It comes from *when* the model runs (*inferred*
from the streaming names above, not traced at runtime).

## What was slow in Rawi

From `~/Library/Logs/Rawi/rawi.log`:
`Recorded 102.1s` → `Timing: transcribe 76654ms … for 215 words`.

1. **All transcription waited for key release.** Wait time grew with the length
   of the dictation.
2. **The resident model wasn't resident.** `vm.swapusage` showed 15.4 GB of
   16 GB swap in use, and the server's RSS was 904 MB against a ~1.9 GB working
   set. The same 98 s clip took 5.2 s on a freshly loaded server and 14.5 s on
   Rawi's idle one.
3. The Core ML encoder takes 55–140 s to load when a server starts (in the log
   as "whisper-server did not answer").

Not reproduced: the 76 s figure itself. Synthetic English, Arabic, quiet and
paused audio never went past 14.5 s. The likely cause is heavier swap at that
moment, but that is inferred, not shown.

## What changed

- `RollingTranscriber`: once 20 s or more of audio is untranscribed, it cuts at
  the first real pause and transcribes that chunk in the background while you
  keep talking. On release only the tail is left. Dictations under 20 s never
  reach it, and a failed chunk falls back to transcribing the whole file.
- `WhisperServerEngine.prefetch()`: if the model has been idle for 45 s, a
  second of silence is sent the moment recording starts, so swapped-out weights
  page back in during speech instead of after it.

## Measured after the change (live server, `RollingLiveBenchmarkTests`)

| Clip | Whole file after release | Rolling, after release | Words |
|---|---|---|---|
| 129 s, sentences with natural pauses | 8244 ms | 872 ms | 380 / 380, no diffs |
| 98 s, multi-second silences spliced mid-word | 3874–13743 ms | 660–1129 ms | 220 / 206 |

The second row is the known limit. A 3–7 s silence in the middle of a word is
indistinguishable from a sentence break by energy, and Whisper drops the
half-sentence before it. The fix is the approach behind MacWhisper's
confirmed/hypothesis names: use segment timestamps and only commit text that
ends before the cut. That needs timestamps from every engine, so it is left for
later.

## Root cause: why it "works a bit and then breaks"

Faster warm transcription did not fix the complaint, because the complaint is
about the cold case. From 243 dictations of a second or more in
`~/Library/Logs/Rawi/rawi.log`, same model and machine, grouped by how long
Rawi sat idle before the dictation:

| Idle before | Median transcribe | Worst | Over 3 s |
|---|---|---|---|
| under 2 min | 1.6 s | 6.1 s | 16% |
| 2–30 min | 3.1 s | 12.2 s | 54% |
| over 30 min | 8.0 s | 76.7 s | 77% |

Used continuously, the model is fast. Left alone, macOS pages its ~2 GB out to
swap (8.8 of 9.2 GB swap in use when measured), and the next dictation pays to
read it back. Several short dictations in the log were cancelled after four or
five seconds of waiting, followed by the app being quit.

No local tuning removes that on a 16 GB machine under this load: a resident
model is memory the OS is free to take back.

## The fix: cloud first, local behind it

`FailoverEngine`, used when `engine` is `groq`:

- Groq's `whisper-large-v3-turbo` answers every dictation, so latency no longer
  depends on idle time or memory pressure. Arabic is supported.
- The connection is opened when recording starts (`prefetch`), so TLS is done
  before release.
- If Groq fails, times out (4 s plus a tenth of the audio length), or rejects
  the key, the same audio goes to local whisper.cpp. Groq is then skipped for
  60 s (30 min for a bad key), so being offline costs one timeout, not one per
  dictation.
- The local fallback is the command line, not the resident server, so it holds
  no memory until it is used.
- Long dictations still roll: chunks go to Groq while you speak.

Also fixed: `prefetch()` was only in a protocol extension, so calls through
`any TranscriptionEngine` went to the empty default. It is now a protocol
requirement.

Not verified: Groq's latency on this machine. That needs a key in
`~/.config/rawi/.env`, which only the user can create.
