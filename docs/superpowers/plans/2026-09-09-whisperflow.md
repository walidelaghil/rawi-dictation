# WhisperFlow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a background macOS menu-bar app that records mic audio while a global hotkey is held, transcribes it locally or via API, cleans it with an LLM, and pastes the result at the cursor of whatever app has focus.

**Architecture:** A Swift 6 SwiftPM executable bundled as `WhisperFlow.app` (`LSUIElement`). A single listen-only `CGEventTap` feeds a `DictationController` state machine, which drives `AudioRecorder → TranscriptionEngine → CleanupProvider → TextInserter`. Every stage sits behind a protocol so it is swappable and unit-testable with fakes. UI is an `NSStatusItem` plus a non-activating `NSPanel` pill.

**Tech Stack:** Swift 6.3, AppKit, AVFoundation, CoreGraphics, SwiftUI (pill only), Swift Testing, `whisper-cli` from Homebrew `whisper-cpp`.

## Global Constraints

- Deployment target: **macOS 14.0** minimum; developed and verified on macOS 26.6.
- Swift tools version **6.0**; strict concurrency enabled.
- **Zero third-party Swift dependencies.** Foundation/AppKit/AVFoundation/SwiftUI only.
- **No telemetry, no analytics, no crash reporting, no account system.** The only outbound network calls permitted are to the explicitly configured transcription/cleanup provider.
- Must remain fully functional with no network when `engine: whispercpp` and `cleanup.provider` is `ollama` or `off`.
- The event tap is **listen-only** (`CGEventTapOptions.listenOnly`). Never consume a keystroke, under any circumstance.
- Config lives at `~/.config/whisperflow/config.json`; secrets at `~/.config/whisperflow/.env`. Secrets are never logged, never written to config, never included in an error message.
- Audio is never silently discarded when a downstream stage fails — retain the WAV and log its path.
- Bundle identifier: `com.welaghil.whisperflow` (stable — TCC grants bind to it).
- Every task ends green: `swift build` and `swift test` both succeed before the commit.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Package.swift` | SwiftPM manifest, two targets |
| `Sources/WhisperFlow/main.swift` | Entry point; builds object graph, starts run loop |
| `Sources/WhisperFlow/App/AppDelegate.swift` | NSApplication lifecycle, wiring |
| `Sources/WhisperFlow/App/DictationController.swift` | The state machine; the only component that knows the whole flow |
| `Sources/WhisperFlow/Input/TapPattern.swift` | Pure press/release → hold / doubleTap / tooShort resolver |
| `Sources/WhisperFlow/Input/HotkeyConfig.swift` | Parses hotkey strings into flag or keycode matchers |
| `Sources/WhisperFlow/Input/HotkeyMonitor.swift` | Owns the CGEventTap, re-arms it, emits events |
| `Sources/WhisperFlow/Audio/WAVWriter.swift` | Incremental RIFF/WAVE writer |
| `Sources/WhisperFlow/Audio/AudioRecorder.swift` | AVAudioEngine capture + 16 kHz mono conversion |
| `Sources/WhisperFlow/Transcribe/TranscriptionEngine.swift` | Protocol + factory |
| `Sources/WhisperFlow/Transcribe/WhisperCppEngine.swift` | Spawns `whisper-cli` |
| `Sources/WhisperFlow/Transcribe/WhisperAPIEngine.swift` | Groq / OpenAI multipart upload |
| `Sources/WhisperFlow/Cleanup/CleanupProvider.swift` | Protocol + factory + shared prompt building |
| `Sources/WhisperFlow/Cleanup/ChatCleanup.swift` | OpenAI / Anthropic / Ollama HTTP implementations |
| `Sources/WhisperFlow/Output/PasteboardStash.swift` | Snapshot/restore all pasteboard types |
| `Sources/WhisperFlow/Output/TextInserter.swift` | Set pasteboard, synthesize Cmd-V |
| `Sources/WhisperFlow/UI/PillView.swift` | SwiftUI pill contents |
| `Sources/WhisperFlow/UI/PillWindow.swift` | Non-activating NSPanel host |
| `Sources/WhisperFlow/UI/MenuBarController.swift` | NSStatusItem and menu |
| `Sources/WhisperFlow/Config/Config.swift` | Codable config model + defaults + load/save |
| `Sources/WhisperFlow/Config/DotEnv.swift` | `.env` parser |
| `Sources/WhisperFlow/Config/FirstRunSetup.swift` | Provider detection on first launch |
| `Sources/WhisperFlow/System/Permissions.swift` | TCC status checks + Settings deep links |
| `Sources/WhisperFlow/System/Log.swift` | File logger with rotation |
| `Tests/WhisperFlowTests/*.swift` | Swift Testing suites for all pure logic |
| `Resources/Info.plist` | Bundle metadata, LSUIElement, usage strings |
| `Makefile` | build / bundle / sign / install |
| `README.md` | Permissions setup, config reference, manual verification checklist |

---

## Task 1: Package skeleton, config model, and `.env` parsing

**Files:**
- Create: `Package.swift`, `.gitignore`
- Create: `Sources/WhisperFlow/Config/Config.swift`
- Create: `Sources/WhisperFlow/Config/DotEnv.swift`
- Create: `Sources/WhisperFlow/main.swift` (temporary stub)
- Test: `Tests/WhisperFlowTests/ConfigTests.swift`, `Tests/WhisperFlowTests/DotEnvTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct Config: Codable, Sendable` with `hotkey: String`, `doubleTapWindowMs: Int`, `minHoldMs: Int`, `maxSessionSeconds: Int`, `engine: EngineKind`, `whispercpp: WhisperCppSettings`, `api: APISettings`, `cleanup: CleanupSettings`, `output: OutputSettings`
  - `enum EngineKind: String, Codable, Sendable { case whispercpp, groq, openai }`
  - `enum CleanupKind: String, Codable, Sendable { case openai, anthropic, ollama, off }`
  - `static Config.default: Config`
  - `static Config.load(from: URL) throws -> Config`
  - `func Config.save(to: URL) throws`
  - `static Config.configDirectory: URL` → `~/.config/whisperflow`
  - `struct DotEnv { init(contents: String); subscript(_ key: String) -> String? ; static func load(from: URL) -> DotEnv }`

**Key decisions to honor:**
- Decoding must be tolerant: every field has a default, so a config missing keys still loads. Implement `init(from decoder:)` with `decodeIfPresent` for each field falling back to `Config.default`.
- `DotEnv` supports `KEY=value`, `KEY="quoted value"`, `export KEY=value`, `#` comments, and blank lines. Values are NOT shell-expanded.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WhisperFlowTests/DotEnvTests.swift
import Testing
@testable import WhisperFlowCore

@Suite("DotEnv") struct DotEnvTests {
    @Test("parses plain, quoted, exported and commented lines") func parses() {
        let env = DotEnv(contents: """
        # a comment
        OPENAI_API_KEY=sk-plain

        export ANTHROPIC_API_KEY="sk-quoted value"
        GROQ_API_KEY='sk-single'
        MALFORMED
        """)
        #expect(env["OPENAI_API_KEY"] == "sk-plain")
        #expect(env["ANTHROPIC_API_KEY"] == "sk-quoted value")
        #expect(env["GROQ_API_KEY"] == "sk-single")
        #expect(env["MALFORMED"] == nil)
        #expect(env["# a comment"] == nil)
    }

    @Test("trims surrounding whitespace but preserves inner") func trims() {
        let env = DotEnv(contents: "  KEY  =  a b  ")
        #expect(env["KEY"] == "a b")
    }
}
```

```swift
// Tests/WhisperFlowTests/ConfigTests.swift
import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("Config") struct ConfigTests {
    @Test("defaults match the spec") func defaults() {
        let c = Config.default
        #expect(c.hotkey == "fn")
        #expect(c.doubleTapWindowMs == 350)
        #expect(c.minHoldMs == 250)
        #expect(c.maxSessionSeconds == 300)
        #expect(c.engine == .whispercpp)
        #expect(c.output.restorePreviousClipboard == false)
    }

    @Test("partial config fills missing keys from defaults") func partial() throws {
        let json = #"{"hotkey":"rightOption","engine":"groq"}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.hotkey == "rightOption")
        #expect(c.engine == .groq)
        #expect(c.maxSessionSeconds == 300)          // filled from default
        #expect(c.cleanup.provider == Config.default.cleanup.provider)
    }

    @Test("round-trips through save and load") func roundTrip() throws {
        var c = Config.default
        c.maxSessionSeconds = 120
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-\(UUID().uuidString).json")
        try c.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Config.load(from: url).maxSessionSeconds == 120)
    }

    @Test("unknown enum value throws rather than silently defaulting") func badEnum() {
        let json = #"{"engine":"nonsense"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: FAIL — no such module `WhisperFlowCore`.

- [ ] **Step 3: Write `Package.swift`**

Two targets: a `WhisperFlowCore` library holding all testable logic, and a thin `WhisperFlow` executable. This split exists because an executable target cannot be imported by a test target.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WhisperFlowCore"),
        .executableTarget(name: "WhisperFlow", dependencies: ["WhisperFlowCore"]),
        .testTarget(name: "WhisperFlowTests", dependencies: ["WhisperFlowCore"]),
    ]
)
```

Move the file layout accordingly: everything except `main.swift` and `AppDelegate.swift` lives under `Sources/WhisperFlowCore/`.

- [ ] **Step 4: Implement `DotEnv` and `Config`**

Write both files to satisfy the Produces block above. `Config.configDirectory` resolves `~/.config/whisperflow` via `FileManager.default.homeDirectoryForCurrentUser`. `save` creates intermediate directories and writes with `.sortedKeys, .prettyPrinted`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: package skeleton, config model, and .env parsing"
```

---

## Task 2: `TapPattern` — hold vs double-tap resolution

This is the subtlest logic in the app and has no system dependencies, so it gets the most thorough tests.

**Files:**
- Create: `Sources/WhisperFlowCore/Input/TapPattern.swift`
- Test: `Tests/WhisperFlowTests/TapPatternTests.swift`

**Interfaces:**
- Consumes: `Config.doubleTapWindowMs`, `Config.minHoldMs`.
- Produces:
```swift
public enum TapOutcome: Equatable, Sendable {
    case beganHold                 // long press started, recording should start
    case endedHold                 // long press released, transcribe
    case pendingShortTap           // too short; hold audio, await possible second tap
    case beganDoubleTap            // second tap inside window; promote to hands-free
    case discardShortTap           // window expired with no second tap
    case stopHandsFree             // any press while a hands-free session runs
    case ignored
}

public struct TapPattern: Sendable {
    public init(doubleTapWindow: Duration, minHold: Duration)
    public mutating func press(at t: ContinuousClock.Instant) -> TapOutcome
    public mutating func release(at t: ContinuousClock.Instant) -> TapOutcome
    /// Called by the controller when the pending-tap timer fires.
    public mutating func pendingExpired(at t: ContinuousClock.Instant) -> TapOutcome
    public mutating func handsFreeDidStart()
    public mutating func reset()
}
```

**Critical semantics (from the spec):**
- The double-tap window is measured from the **first press**, not from its release.
- Inside a hands-free session, **any** press returns `.stopHandsFree` regardless of hold duration.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import WhisperFlowCore

@Suite("TapPattern") struct TapPatternTests {
    let clock = ContinuousClock()
    func make() -> TapPattern {
        TapPattern(doubleTapWindow: .milliseconds(350), minHold: .milliseconds(250))
    }

    @Test("a long press begins and ends a hold") func longPress() {
        var p = make(); let t0 = clock.now
        #expect(p.press(at: t0) == .beganHold)
        #expect(p.release(at: t0.advanced(by: .milliseconds(900))) == .endedHold)
    }

    @Test("a press released under minHold becomes pending, not a hold") func shortPress() {
        var p = make(); let t0 = clock.now
        #expect(p.press(at: t0) == .beganHold)
        #expect(p.release(at: t0.advanced(by: .milliseconds(120))) == .pendingShortTap)
    }

    @Test("a second press inside the window promotes to hands-free") func doubleTap() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(120)))
        #expect(p.press(at: t0.advanced(by: .milliseconds(300))) == .beganDoubleTap)
    }

    @Test("the window is measured from the first press, not its release") func windowOrigin() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(240)))   // just under minHold
        // 300ms after release is 540ms after the first press -> outside the window
        #expect(p.press(at: t0.advanced(by: .milliseconds(540))) == .beganHold)
    }

    @Test("an expired pending tap is discarded") func expiry() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(100)))
        #expect(p.pendingExpired(at: t0.advanced(by: .milliseconds(350))) == .discardShortTap)
    }

    @Test("exactly at the boundary counts as inside the window") func boundary() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(100)))
        #expect(p.press(at: t0.advanced(by: .milliseconds(350))) == .beganDoubleTap)
    }

    @Test("any press stops a hands-free session, however brief") func stopsHandsFree() {
        var p = make(); let t0 = clock.now
        p.handsFreeDidStart()
        #expect(p.press(at: t0) == .stopHandsFree)
        #expect(p.release(at: t0.advanced(by: .milliseconds(5))) == .ignored)
    }

    @Test("a long press stops a hands-free session too") func longPressStopsHandsFree() {
        var p = make(); let t0 = clock.now
        p.handsFreeDidStart()
        #expect(p.press(at: t0) == .stopHandsFree)
        #expect(p.release(at: t0.advanced(by: .seconds(2))) == .ignored)
    }

    @Test("a release with no matching press is ignored") func strayRelease() {
        var p = make()
        #expect(p.release(at: clock.now) == .ignored)
    }

    @Test("reset returns to a clean idle state") func resets() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0); p.reset()
        #expect(p.release(at: t0.advanced(by: .seconds(1))) == .ignored)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TapPattern`
Expected: FAIL — `TapPattern` not found.

- [ ] **Step 3: Implement `TapPattern`**

Model it as an internal `enum Phase { case idle, holding(since: Instant), pendingSecondTap(firstPress: Instant), handsFree }`. `press` and `release` switch on the phase. The `pendingSecondTap` case stores the **first press** instant so the window comparison uses it directly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TapPattern`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Input/TapPattern.swift Tests/WhisperFlowTests/TapPatternTests.swift
git commit -m "feat: hold vs double-tap resolution logic"
```

---

## Task 3: `WAVWriter` — incremental 16 kHz mono PCM

**Files:**
- Create: `Sources/WhisperFlowCore/Audio/WAVWriter.swift`
- Test: `Tests/WhisperFlowTests/WAVWriterTests.swift`

**Interfaces:**
- Produces:
```swift
public final class WAVWriter {
    public init(url: URL, sampleRate: Int = 16_000, channels: Int = 1) throws
    public func append(_ samples: [Int16]) throws
    public func finalize() throws          // patches RIFF + data chunk sizes
    public var frameCount: Int { get }
    public var duration: Duration { get }
}
```

**Why it matters:** whisper-cli accepts only 16 kHz mono PCM WAV. A wrong header produces silent garbage transcripts rather than an error, so the header bytes are asserted explicitly.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("WAVWriter") struct WAVWriterTests {
    func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-\(UUID().uuidString).wav")
    }

    @Test("writes a valid 44-byte canonical header") func header() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.append([Int16](repeating: 0, count: 16_000))
        try w.finalize()

        let d = try Data(contentsOf: url)
        #expect(d.count == 44 + 32_000)
        #expect(d[0..<4].elementsEqual("RIFF".utf8))
        #expect(d[8..<12].elementsEqual("WAVE".utf8))
        #expect(d[12..<16].elementsEqual("fmt ".utf8))
        #expect(d[36..<40].elementsEqual("data".utf8))

        func u32(_ o: Int) -> UInt32 { d[o..<o+4].reduce(0) { ($0 >> 0) | UInt32($1) << (8 * UInt32(d[o..<o+4].count - ($0 == 0 ? 4 : 0))) } }
        #expect(le32(d, 4)  == UInt32(36 + 32_000))   // RIFF size
        #expect(le32(d, 40) == UInt32(32_000))        // data size
        #expect(le32(d, 24) == 16_000)                // sample rate
        #expect(le16(d, 22) == 1)                     // mono
        #expect(le16(d, 34) == 16)                    // bits per sample
    }

    @Test("frameCount and duration track appended samples") func counts() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.append([Int16](repeating: 1, count: 8_000))
        try w.append([Int16](repeating: 2, count: 8_000))
        try w.finalize()
        #expect(w.frameCount == 16_000)
        #expect(w.duration == .seconds(1))
    }

    @Test("an empty recording still produces a readable file") func empty() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.finalize()
        let d = try Data(contentsOf: url)
        #expect(d.count == 44)
        #expect(le32(d, 40) == 0)
    }
}

// Little-endian readers used by the assertions above.
func le32(_ d: Data, _ o: Int) -> UInt32 {
    UInt32(d[o]) | UInt32(d[o+1]) << 8 | UInt32(d[o+2]) << 16 | UInt32(d[o+3]) << 24
}
func le16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[o]) | UInt16(d[o+1]) << 8 }
```

Delete the stray `u32` helper inside `header()` when implementing — `le32`/`le16` are the real helpers.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WAVWriter`
Expected: FAIL — `WAVWriter` not found.

- [ ] **Step 3: Implement `WAVWriter`**

Write a 44-byte placeholder header on `init`, append raw little-endian Int16 via a `FileHandle`, and on `finalize()` seek to offsets 4 and 40 to patch `RIFF` size (`36 + dataBytes`) and `data` size (`dataBytes`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WAVWriter`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Audio/WAVWriter.swift Tests/WhisperFlowTests/WAVWriterTests.swift
git commit -m "feat: incremental 16kHz mono WAV writer"
```

---

## Task 4: `AudioRecorder` — capture and 16 kHz conversion

**Files:**
- Create: `Sources/WhisperFlowCore/Audio/AudioRecorder.swift`
- Test: `Tests/WhisperFlowTests/AudioConversionTests.swift`

**Interfaces:**
- Consumes: `WAVWriter`.
- Produces:
```swift
public protocol AudioRecording: AnyObject, Sendable {
    func start(to url: URL) throws
    func stop() throws -> RecordingResult        // finalizes the WAV
    func cancel()                                // stops and deletes the file
    var level: Double { get }                    // smoothed RMS, 0...1
    var isRecording: Bool { get }
}

public struct RecordingResult: Sendable {
    public let url: URL
    public let duration: Duration
}

public final class AudioRecorder: AudioRecording { public init() }

public enum AudioError: Error, LocalizedError {
    case microphonePermissionDenied
    case engineStartFailed(String)
    case converterUnavailable
}
```

**Implementation notes:**
- Tap `AVAudioEngine.inputNode` at its *hardware* format. Do not assume 48 kHz — read `inputNode.outputFormat(forBus: 0)` and build an `AVAudioConverter` to `AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)`.
- Convert with `.convert(to:error:withInputFrom:)` using an input block; the ratio is not integral in general, so never assume a fixed output buffer size.
- Compute smoothed RMS on the *converted* buffer: `level = 0.85 * level + 0.15 * newRMS`.
- `stop()` must remove the tap and stop the engine **before** finalizing the WAV.
- Guard on `AVCaptureDevice.authorizationStatus(for: .audio)`; throw `.microphonePermissionDenied` rather than starting a silent engine.

The AVAudioEngine path itself needs a live microphone, so it is covered by the README's manual checklist. The extractable arithmetic is tested here.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import AVFoundation
@testable import WhisperFlowCore

@Suite("Audio conversion") struct AudioConversionTests {
    @Test("rms of silence is zero, of full-scale is one") func rms() {
        #expect(rmsLevel([Int16](repeating: 0, count: 512)) == 0.0)
        let full = [Int16](repeating: Int16.max, count: 512)
        #expect(abs(rmsLevel(full) - 1.0) < 0.01)
    }

    @Test("rms of a half-scale square wave is one half") func halfScale() {
        let half = [Int16](repeating: Int16.max / 2, count: 512)
        #expect(abs(rmsLevel(half) - 0.5) < 0.02)
    }

    @Test("target format is 16kHz mono int16") func targetFormat() {
        let f = AudioRecorder.whisperFormat
        #expect(f.sampleRate == 16_000)
        #expect(f.channelCount == 1)
        #expect(f.commonFormat == .pcmFormatInt16)
    }

    @Test("level smoothing converges toward the input") func smoothing() {
        var l = 0.0
        for _ in 0..<100 { l = smoothLevel(previous: l, sample: 1.0) }
        #expect(l > 0.99)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail** — `swift test --filter "Audio conversion"` → FAIL, symbols not found.

- [ ] **Step 3: Implement** `AudioRecorder`, exposing `rmsLevel(_:)`, `smoothLevel(previous:sample:)` and `static whisperFormat` at internal (testable) visibility.

- [ ] **Step 4: Run tests** — `swift test --filter "Audio conversion"` → PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Audio/AudioRecorder.swift Tests/WhisperFlowTests/AudioConversionTests.swift
git commit -m "feat: microphone capture with 16kHz mono conversion"
```

---

## Task 5: `WhisperCppEngine` — local transcription

**Files:**
- Create: `Sources/WhisperFlowCore/Transcribe/TranscriptionEngine.swift`
- Create: `Sources/WhisperFlowCore/Transcribe/WhisperCppEngine.swift`
- Test: `Tests/WhisperFlowTests/WhisperCppEngineTests.swift`

**Interfaces:**
```swift
public protocol TranscriptionEngine: AnyObject, Sendable {
    func transcribe(wav: URL) async throws -> String
    func cancel()
}

public enum TranscriptionError: Error, LocalizedError {
    case binaryNotFound(String)
    case modelNotFound(String)
    case processFailed(exitCode: Int32, stderrTail: String)
    case cancelled
    case emptyResult
    case apiError(status: Int, message: String)
    case missingAPIKey(String)
}

public final class WhisperCppEngine: TranscriptionEngine {
    public init(binary: String, model: String, language: String, threads: Int)
    public static func resolveBinary(_ configured: String) -> URL?
    public static func cleanTranscript(_ raw: String) -> String
}
```

**Verified invocation** (confirmed against `whisper-cpp` 1.8.x on this machine):

```
whisper-cli -m <model> -f <wav> -nt -np -sns -l <lang> -t <threads>
```

- `-nt` no timestamps, `-np` no prints, `-sns` suppress non-speech tokens.
- **Results go to stdout; ggml/Metal diagnostics go to stderr.** Read them into separate pipes and never merge them — merging corrupts the transcript.
- The very first invocation after install compiles Metal shaders and takes ~30 s. Subsequent runs start in ~0.1 s. The README tells the user to run it once during setup to warm the cache.
- `resolveBinary` order: configured absolute path → `PATH` lookup → `/opt/homebrew/bin/whisper-cli` → `/usr/local/bin/whisper-cli`.
- `cancel()` calls `process.terminate()`; the awaiting continuation resumes with `.cancelled`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("WhisperCppEngine") struct WhisperCppEngineTests {
    @Test("strips residual bracket tokens and collapses whitespace") func clean() {
        #expect(WhisperCppEngine.cleanTranscript("  [BLANK_AUDIO]\n Hello   there. \n")
                == "Hello there.")
        #expect(WhisperCppEngine.cleanTranscript("(wind blowing) Testing one two")
                == "Testing one two")
        #expect(WhisperCppEngine.cleanTranscript("Line one.\nLine two.")
                == "Line one. Line two.")
    }

    @Test("an all-noise transcript cleans to empty") func allNoise() {
        #expect(WhisperCppEngine.cleanTranscript("[BLANK_AUDIO]").isEmpty)
    }

    @Test("resolves the homebrew binary on this machine") func resolve() throws {
        let url = try #require(WhisperCppEngine.resolveBinary("whisper-cli"))
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
    }

    @Test("a missing binary resolves to nil") func missing() {
        #expect(WhisperCppEngine.resolveBinary("definitely-not-a-real-binary-xyz") == nil)
    }

    @Test("a missing model surfaces modelNotFound before spawning") func noModel() async {
        let e = WhisperCppEngine(binary: "whisper-cli", model: "/nope/missing.bin",
                                 language: "en", threads: 4)
        await #expect(throws: TranscriptionError.self) {
            _ = try await e.transcribe(wav: URL(fileURLWithPath: "/tmp/x.wav"))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail** — `swift test --filter WhisperCppEngine` → FAIL.

- [ ] **Step 3: Implement** the protocol, error enum, and engine. Use `withTaskCancellationHandler` wrapping a `withCheckedThrowingContinuation` around `Process.terminationHandler`.

- [ ] **Step 4: Run tests** — PASS, 5 tests.

- [ ] **Step 5: Download a model and verify end-to-end by hand**

```bash
mkdir -p ~/Library/Application\ Support/WhisperFlow/models
curl -L -o ~/Library/Application\ Support/WhisperFlow/models/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
say -o /tmp/wf-test.wav --data-format=LEI16@16000 "This is a test of the dictation system"
whisper-cli -m ~/Library/Application\ Support/WhisperFlow/models/ggml-small.en.bin \
  -f /tmp/wf-test.wav -nt -np -sns -l en 2>/dev/null
```
Expected: the spoken sentence printed on stdout with nothing else.

- [ ] **Step 6: Commit**

```bash
git add Sources/WhisperFlowCore/Transcribe Tests/WhisperFlowTests/WhisperCppEngineTests.swift
git commit -m "feat: local whisper.cpp transcription engine"
```

---

## Task 6: `WhisperAPIEngine` — Groq and OpenAI

**Files:**
- Create: `Sources/WhisperFlowCore/Transcribe/WhisperAPIEngine.swift`
- Test: `Tests/WhisperFlowTests/WhisperAPIEngineTests.swift`

**Interfaces:**
```swift
public final class WhisperAPIEngine: TranscriptionEngine {
    public init(provider: EngineKind, apiKey: String, model: String,
                session: URLSession = .shared)
    static func multipartBody(boundary: String, model: String,
                              filename: String, wav: Data) -> Data
    static func endpoint(for provider: EngineKind) -> URL
    static func parseResponse(_ data: Data) throws -> String
}
```

- Groq: `https://api.groq.com/openai/v1/audio/transcriptions`, model `whisper-large-v3-turbo`.
- OpenAI: `https://api.openai.com/v1/audio/transcriptions`, model `whisper-1`.
- Both take the same multipart form (`file`, `model`, `response_format=json`) and return `{"text": "..."}`.
- API keys come from `.env` only. **Never** log the key or echo it in an error.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("WhisperAPIEngine") struct WhisperAPIEngineTests {
    @Test("multipart body carries both parts with correct boundaries") func body() {
        let d = WhisperAPIEngine.multipartBody(boundary: "BOUND", model: "whisper-1",
                                               filename: "a.wav", wav: Data([1,2,3]))
        let s = String(decoding: d, as: UTF8.self)
        #expect(s.contains("--BOUND\r\n"))
        #expect(s.contains(#"name="model""#))
        #expect(s.contains("whisper-1"))
        #expect(s.contains(#"name="file"; filename="a.wav""#))
        #expect(s.contains("Content-Type: audio/wav"))
        #expect(s.hasSuffix("--BOUND--\r\n"))
    }

    @Test("endpoints match each provider") func endpoints() {
        #expect(WhisperAPIEngine.endpoint(for: .groq).host == "api.groq.com")
        #expect(WhisperAPIEngine.endpoint(for: .openai).host == "api.openai.com")
    }

    @Test("parses the text field") func parse() throws {
        #expect(try WhisperAPIEngine.parseResponse(Data(#"{"text":"hello"}"#.utf8)) == "hello")
    }

    @Test("an error payload throws rather than returning empty") func parseError() {
        #expect(throws: (any Error).self) {
            try WhisperAPIEngine.parseResponse(Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter WhisperAPIEngine` → FAIL.
- [ ] **Step 3: Implement.** Use `URLSession.upload(for:from:)`; cancellation via the task handle.
- [ ] **Step 4: Run tests** — PASS, 4 tests.
- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Transcribe/WhisperAPIEngine.swift Tests/WhisperFlowTests/WhisperAPIEngineTests.swift
git commit -m "feat: Groq and OpenAI whisper API transcription engine"
```

---

## Task 7: `CleanupProvider` — all four implementations

**Files:**
- Create: `Sources/WhisperFlowCore/Cleanup/CleanupProvider.swift`
- Create: `Sources/WhisperFlowCore/Cleanup/ChatCleanup.swift`
- Test: `Tests/WhisperFlowTests/CleanupTests.swift`

**Interfaces:**
```swift
public protocol CleanupProvider: AnyObject, Sendable {
    func clean(_ transcript: String) async throws -> String
    func cancel()
}

public final class NoopCleanup: CleanupProvider { public init() }

public final class ChatCleanup: CleanupProvider {
    public init(kind: CleanupKind, apiKey: String?, model: String,
                prompt: String, session: URLSession = .shared)
    static func requestBody(kind: CleanupKind, model: String,
                            prompt: String, transcript: String) throws -> Data
    static func parse(kind: CleanupKind, _ data: Data) throws -> String
    static func endpoint(kind: CleanupKind) -> URL
}

public enum CleanupError: Error { case missingAPIKey(String), badResponse(String), cancelled }

public let defaultCleanupPrompt = """
You clean up raw speech-to-text transcripts. Remove filler words (um, uh, like, \
you know, I mean, sort of, basically) and false starts. Fix punctuation and sentence \
boundaries. Apply sentence casing and capitalise proper nouns. Do not add, remove, \
summarise, answer, or reword any content beyond this. If the transcript is already \
clean, return it unchanged. Return only the corrected text with no preamble, \
quotes, or commentary.
"""
```

**Endpoints and shapes:**
| Kind | URL | Auth header | Response path |
|---|---|---|---|
| `openai` | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` | `choices[0].message.content` |
| `anthropic` | `https://api.anthropic.com/v1/messages` | `x-api-key` + `anthropic-version: 2023-06-01` | `content[0].text` |
| `ollama` | `http://localhost:11434/api/chat` | none | `message.content` |

Anthropic puts the instruction in a top-level `system` field, not a system message; OpenAI and Ollama use a `system` role message. `ollama` must send `"stream": false`.

**Failure policy:** cleanup failure is non-fatal. `DictationController` catches it, logs, and inserts the raw transcript. That behaviour is asserted in Task 10, not here.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("Cleanup") struct CleanupTests {
    @Test("noop returns its input unchanged") func noop() async throws {
        #expect(try await NoopCleanup().clean("  um so yeah  ") == "  um so yeah  ")
    }

    @Test("openai body uses a system role message") func openaiBody() throws {
        let d = try ChatCleanup.requestBody(kind: .openai, model: "gpt-4o-mini",
                                            prompt: "PROMPT", transcript: "TEXT")
        let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        let msgs = j["messages"] as! [[String: String]]
        #expect(msgs[0]["role"] == "system")
        #expect(msgs[0]["content"] == "PROMPT")
        #expect(msgs[1]["content"] == "TEXT")
        #expect(j["model"] as? String == "gpt-4o-mini")
    }

    @Test("anthropic body uses a top-level system field") func anthropicBody() throws {
        let d = try ChatCleanup.requestBody(kind: .anthropic, model: "claude-haiku-4-5-20251001",
                                            prompt: "PROMPT", transcript: "TEXT")
        let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        #expect(j["system"] as? String == "PROMPT")
        #expect(j["max_tokens"] != nil)
        let msgs = j["messages"] as! [[String: Any]]
        #expect(msgs.count == 1)
        #expect(msgs[0]["role"] as? String == "user")
    }

    @Test("ollama body disables streaming") func ollamaBody() throws {
        let d = try ChatCleanup.requestBody(kind: .ollama, model: "qwen2.5:3b",
                                            prompt: "P", transcript: "T")
        let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        #expect(j["stream"] as? Bool == false)
    }

    @Test("each provider response shape parses") func parsing() throws {
        #expect(try ChatCleanup.parse(kind: .openai,
            Data(#"{"choices":[{"message":{"content":"A"}}]}"#.utf8)) == "A")
        #expect(try ChatCleanup.parse(kind: .anthropic,
            Data(#"{"content":[{"type":"text","text":"B"}]}"#.utf8)) == "B")
        #expect(try ChatCleanup.parse(kind: .ollama,
            Data(#"{"message":{"content":"C"}}"#.utf8)) == "C")
    }

    @Test("a malformed response throws") func badParse() {
        #expect(throws: (any Error).self) {
            try ChatCleanup.parse(kind: .openai, Data(#"{"choices":[]}"#.utf8))
        }
    }

    @Test("endpoints are correct per provider") func endpoints() {
        #expect(ChatCleanup.endpoint(kind: .ollama).absoluteString
                == "http://localhost:11434/api/chat")
        #expect(ChatCleanup.endpoint(kind: .anthropic).path == "/v1/messages")
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter Cleanup` → FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run tests** — PASS, 7 tests.
- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Cleanup Tests/WhisperFlowTests/CleanupTests.swift
git commit -m "feat: LLM cleanup providers for openai, anthropic, ollama, and off"
```

---

## Task 8: `FirstRunSetup` — provider detection

**Files:**
- Create: `Sources/WhisperFlowCore/Config/FirstRunSetup.swift`
- Test: `Tests/WhisperFlowTests/FirstRunSetupTests.swift`

**Interfaces:**
```swift
public struct Probes: Sendable {
    public var envKeys: Set<String>
    public var ollamaReachable: Bool
    public var whisperBinaryFound: Bool
    public var whisperModelFound: Bool
    public init(envKeys: Set<String>, ollamaReachable: Bool,
                whisperBinaryFound: Bool, whisperModelFound: Bool)
}

public enum FirstRunSetup {
    public static func detect(_ p: Probes) -> Config
    public static func liveProbes(env: DotEnv) async -> Probes
}
```

**Detection rules (exact, from the spec):**
- `engine`: `whispercpp` if binary **and** model found; else `groq` if `GROQ_API_KEY`; else `openai` if `OPENAI_API_KEY`; else `whispercpp` (and the menu bar shows a setup warning).
- `cleanup.provider`: `openai` if `OPENAI_API_KEY`; else `anthropic` if `ANTHROPIC_API_KEY`; else `ollama` if reachable; else `off`.
- `liveProbes` checks Ollama with a 500 ms-timeout GET to `http://localhost:11434/api/tags`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import WhisperFlowCore

@Suite("FirstRunSetup") struct FirstRunSetupTests {
    func probes(env: Set<String> = [], ollama: Bool = false,
                bin: Bool = true, model: Bool = true) -> Probes {
        Probes(envKeys: env, ollamaReachable: ollama,
               whisperBinaryFound: bin, whisperModelFound: model)
    }

    @Test("local whisper wins when binary and model are present") func localEngine() {
        #expect(FirstRunSetup.detect(probes(env: ["GROQ_API_KEY"])).engine == .whispercpp)
    }

    @Test("falls back to groq when the model is missing") func groqFallback() {
        #expect(FirstRunSetup.detect(probes(env: ["GROQ_API_KEY"], model: false)).engine == .groq)
    }

    @Test("falls back to openai when only that key exists") func openaiFallback() {
        #expect(FirstRunSetup.detect(probes(env: ["OPENAI_API_KEY"], bin: false, model: false)).engine == .openai)
    }

    @Test("openai key wins for cleanup") func cleanupOpenAI() {
        #expect(FirstRunSetup.detect(probes(env: ["OPENAI_API_KEY"], ollama: true))
                .cleanup.provider == .openai)
    }

    @Test("anthropic is used when it is the only key") func cleanupAnthropic() {
        #expect(FirstRunSetup.detect(probes(env: ["ANTHROPIC_API_KEY"], ollama: true))
                .cleanup.provider == .anthropic)
    }

    @Test("ollama is used when no key exists but it is running") func cleanupOllama() {
        #expect(FirstRunSetup.detect(probes(ollama: true)).cleanup.provider == .ollama)
    }

    @Test("cleanup is off with no keys and no ollama") func cleanupOff() {
        #expect(FirstRunSetup.detect(probes()).cleanup.provider == .off)
    }

    @Test("detection never leaves the hotkey unset") func hotkey() {
        #expect(FirstRunSetup.detect(probes()).hotkey == "fn")
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run tests** — PASS, 8 tests.
- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Config/FirstRunSetup.swift Tests/WhisperFlowTests/FirstRunSetupTests.swift
git commit -m "feat: first-run provider detection"
```

---

## Task 9: `TextInserter` and `PasteboardStash`

**Files:**
- Create: `Sources/WhisperFlowCore/Output/PasteboardStash.swift`
- Create: `Sources/WhisperFlowCore/Output/TextInserter.swift`
- Test: `Tests/WhisperFlowTests/PasteboardTests.swift`

**Interfaces:**
```swift
public protocol TextInserting: AnyObject, Sendable {
    /// Returns false when Accessibility is not granted; caller then tells the
    /// user the text is on the clipboard and must be pasted by hand.
    func insert(_ text: String, restoringClipboard: Bool) -> Bool
}

public final class TextInserter: TextInserting {
    public init(restoreDelay: Duration = .milliseconds(300))
}

public struct PasteboardStash: Sendable {
    public static func capture(_ pb: NSPasteboard) -> PasteboardStash
    public func restore(to pb: NSPasteboard)
    public var isEmpty: Bool { get }
}
```

**Implementation notes:**
- `capture` snapshots **every** `NSPasteboardItem` and all of its type/data pairs, so images and rich text survive a restore.
- Synthesize Cmd-V with a `CGEventSource(stateID: .combinedSessionState)`, virtual key `9` (`kVK_ANSI_V`), `flags = .maskCommand`, posted to `.cghidEventTap`, keyDown then keyUp.
- Check `AXIsProcessTrusted()` first and return `false` without pasting if untrusted — the text still goes on the clipboard.
- When `restoringClipboard` is true, restore after `restoreDelay` on a background queue. Document the race in the README.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import AppKit
@testable import WhisperFlowCore

@Suite("Pasteboard", .serialized) struct PasteboardTests {
    @Test("captures and restores a string") func roundTrip() {
        let pb = NSPasteboard(name: .init("wf-test-\(UUID().uuidString)"))
        pb.clearContents(); pb.setString("original", forType: .string)

        let stash = PasteboardStash.capture(pb)
        pb.clearContents(); pb.setString("replacement", forType: .string)
        #expect(pb.string(forType: .string) == "replacement")

        stash.restore(to: pb)
        #expect(pb.string(forType: .string) == "original")
    }

    @Test("captures an empty pasteboard without crashing") func empty() {
        let pb = NSPasteboard(name: .init("wf-test-\(UUID().uuidString)"))
        pb.clearContents()
        let stash = PasteboardStash.capture(pb)
        #expect(stash.isEmpty)
        stash.restore(to: pb)
        #expect(pb.string(forType: .string) == nil)
    }

    @Test("preserves multiple types on one item") func multiType() {
        let pb = NSPasteboard(name: .init("wf-test-\(UUID().uuidString)"))
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setString("<b>rich</b>", forType: .html)
        pb.writeObjects([item])

        let stash = PasteboardStash.capture(pb)
        pb.clearContents(); pb.setString("gone", forType: .string)
        stash.restore(to: pb)

        #expect(pb.string(forType: .string) == "plain")
        #expect(pb.string(forType: .html) == "<b>rich</b>")
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run tests** — PASS, 3 tests.
- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Output Tests/WhisperFlowTests/PasteboardTests.swift
git commit -m "feat: clipboard stash and cursor text insertion"
```

---

## Task 10: `DictationController` — the state machine

The heart of the app. Because every dependency is a protocol, this task is fully testable with fakes and gets the second-most thorough test suite after `TapPattern`.

**Files:**
- Create: `Sources/WhisperFlowCore/App/DictationController.swift`
- Test: `Tests/WhisperFlowTests/DictationControllerTests.swift`

**Interfaces:**
```swift
public enum DictationState: Equatable, Sendable {
    case idle
    case recording(mode: RecordingMode, startedAt: ContinuousClock.Instant)
    case transcribing
    case cleaning
    case inserting
    case error(String)
}

public enum RecordingMode: Equatable, Sendable { case pushToTalk, handsFree }

@MainActor public final class DictationController {
    public init(config: Config,
                recorder: any AudioRecording,
                engine: any TranscriptionEngine,
                cleanup: any CleanupProvider,
                inserter: any TextInserting,
                log: any Logging)

    public private(set) var state: DictationState
    public var onStateChange: ((DictationState) -> Void)?

    public func handle(_ outcome: TapOutcome) async
    public func cancelRequested() async          // Esc
    public func sessionTimedOut() async          // 5-minute auto-stop
    public var isEnabled: Bool { get set }       // menu bar toggle
}
```

**Behaviour that must hold:**
1. `.beganHold` / `.beganDoubleTap` start recording only from `.idle`.
2. `.endedHold` and `.stopHandsFree` run the full pipeline: transcribe → clean → insert → idle.
3. `cancelRequested()` from `.recording` drops the audio; from `.transcribing`/`.cleaning` cancels the in-flight work; from `.idle` does nothing.
4. **A cleanup failure inserts the raw transcript** rather than failing the dictation.
5. A transcription failure retains the WAV and logs its path.
6. An empty transcript returns to `.idle` silently without pasting.
7. When `isEnabled == false`, every tap outcome is ignored.
8. `sessionTimedOut()` only acts in `.recording(mode: .handsFree)`.

- [ ] **Step 1: Write the fakes**

```swift
// Tests/WhisperFlowTests/Fakes.swift
import Foundation
@testable import WhisperFlowCore

final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var level = 0.0
    var cancelled = false
    var startedURLs: [URL] = []
    var stubDuration: Duration = .seconds(3)
    func start(to url: URL) throws { isRecording = true; startedURLs.append(url) }
    func stop() throws -> RecordingResult {
        isRecording = false
        return RecordingResult(url: startedURLs.last!, duration: stubDuration)
    }
    func cancel() { isRecording = false; cancelled = true }
}

final class FakeEngine: TranscriptionEngine, @unchecked Sendable {
    var result: Result<String, Error> = .success("raw transcript")
    var cancelCount = 0
    var callCount = 0
    func transcribe(wav: URL) async throws -> String {
        callCount += 1
        return try result.get()
    }
    func cancel() { cancelCount += 1 }
}

final class FakeCleanup: CleanupProvider, @unchecked Sendable {
    var result: Result<String, Error> = .success("Cleaned transcript.")
    var received: [String] = []
    func clean(_ t: String) async throws -> String { received.append(t); return try result.get() }
    func cancel() {}
}

final class FakeInserter: TextInserting, @unchecked Sendable {
    var inserted: [String] = []
    var succeed = true
    func insert(_ text: String, restoringClipboard: Bool) -> Bool {
        inserted.append(text); return succeed
    }
}

final class FakeLog: Logging, @unchecked Sendable {
    var lines: [String] = []
    func log(_ level: LogLevel, _ message: String) { lines.append("\(level): \(message)") }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
@testable import WhisperFlowCore

@MainActor @Suite("DictationController") struct DictationControllerTests {
    func make(cleanupFails: Bool = false, transcript: String = "raw transcript")
        -> (DictationController, FakeRecorder, FakeEngine, FakeCleanup, FakeInserter, FakeLog) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        e.result = .success(transcript)
        if cleanupFails { c.result = .failure(CleanupError.badResponse("boom")) }
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: l)
        return (ctl, r, e, c, i, l)
    }

    @Test("a full push-to-talk cycle inserts cleaned text and returns to idle") func happyPath() async {
        let (ctl, r, _, c, i, _) = make()
        await ctl.handle(.beganHold)
        #expect(r.isRecording)
        await ctl.handle(.endedHold)
        #expect(c.received == ["raw transcript"])
        #expect(i.inserted == ["Cleaned transcript."])
        #expect(ctl.state == .idle)
    }

    @Test("a double tap starts a hands-free recording") func handsFree() async {
        let (ctl, r, _, _, _, _) = make()
        await ctl.handle(.beganDoubleTap)
        #expect(r.isRecording)
        #expect(ctl.state == .recording(mode: .handsFree, startedAt: ctl.recordingStartedAt!))
    }

    @Test("stopHandsFree runs the pipeline") func handsFreeStop() async {
        let (ctl, _, _, _, i, _) = make()
        await ctl.handle(.beganDoubleTap)
        await ctl.handle(.stopHandsFree)
        #expect(i.inserted.count == 1)
        #expect(ctl.state == .idle)
    }

    @Test("esc while recording drops the audio and inserts nothing") func cancelRecording() async {
        let (ctl, r, e, _, i, _) = make()
        await ctl.handle(.beganHold)
        await ctl.cancelRequested()
        #expect(r.cancelled)
        #expect(e.callCount == 0)
        #expect(i.inserted.isEmpty)
        #expect(ctl.state == .idle)
    }

    @Test("esc while idle does nothing") func cancelIdle() async {
        let (ctl, r, _, _, _, _) = make()
        await ctl.cancelRequested()
        #expect(!r.cancelled)
        #expect(ctl.state == .idle)
    }

    @Test("a cleanup failure still inserts the raw transcript") func cleanupFallback() async {
        let (ctl, _, _, _, i, l) = make(cleanupFails: true)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(i.inserted == ["raw transcript"])
        #expect(l.lines.contains { $0.contains("cleanup") })
        #expect(ctl.state == .idle)
    }

    @Test("an empty transcript inserts nothing and returns to idle") func emptyTranscript() async {
        let (ctl, _, _, _, i, _) = make(transcript: "   ")
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(i.inserted.isEmpty)
        #expect(ctl.state == .idle)
    }

    @Test("a transcription failure retains the wav and logs its path") func transcriptionFailure() async {
        let (ctl, r, e, _, i, l) = make()
        e.result = .failure(TranscriptionError.emptyResult)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(i.inserted.isEmpty)
        #expect(l.lines.contains { $0.contains(r.startedURLs.last!.lastPathComponent) })
    }

    @Test("the 5 minute timeout stops only a hands-free session") func timeout() async {
        let (ctl, _, _, _, i, _) = make()
        await ctl.handle(.beganDoubleTap)
        await ctl.sessionTimedOut()
        #expect(i.inserted.count == 1)

        let (ctl2, _, _, _, i2, _) = make()
        await ctl2.handle(.beganHold)
        await ctl2.sessionTimedOut()
        #expect(i2.inserted.isEmpty)          // push-to-talk is unaffected
    }

    @Test("a disabled controller ignores every tap") func disabled() async {
        let (ctl, r, _, _, _, _) = make()
        ctl.isEnabled = false
        await ctl.handle(.beganHold)
        #expect(!r.isRecording)
        #expect(ctl.state == .idle)
    }

    @Test("a failed paste leaves the text on the clipboard and reports it") func pasteDenied() async {
        let (ctl, _, _, _, i, l) = make()
        i.succeed = false
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(l.lines.contains { $0.lowercased().contains("accessibility") })
    }

    @Test("a second beganHold while recording is ignored") func reentrancy() async {
        let (ctl, r, _, _, _, _) = make()
        await ctl.handle(.beganHold)
        r.startedURLs.removeAll()
        await ctl.handle(.beganHold)
        #expect(r.startedURLs.isEmpty)
    }
}
```

- [ ] **Step 3: Run to verify failure** — `swift test --filter DictationController` → FAIL.
- [ ] **Step 4: Implement** `DictationController`, plus `Logging`/`LogLevel` in `System/Log.swift` (protocol + a real file logger with 5 MB rotation). Expose `recordingStartedAt` internally for the test above.
- [ ] **Step 5: Run tests** — PASS, 12 tests.
- [ ] **Step 6: Commit**

```bash
git add Sources/WhisperFlowCore/App Sources/WhisperFlowCore/System/Log.swift Tests/WhisperFlowTests
git commit -m "feat: dictation state machine with cancellation and failure fallbacks"
```

---

## Task 11: `HotkeyMonitor` and `HotkeyConfig` — the event tap

**Files:**
- Create: `Sources/WhisperFlowCore/Input/HotkeyConfig.swift`
- Create: `Sources/WhisperFlowCore/Input/HotkeyMonitor.swift`
- Test: `Tests/WhisperFlowTests/HotkeyConfigTests.swift`

**Interfaces:**
```swift
public enum HotkeyMatcher: Equatable, Sendable {
    case modifierFlag(CGEventFlags)        // fn, rightOption...
    case keyCode(UInt16, modifiers: CGEventFlags)
}

public enum HotkeyConfig {
    public static func parse(_ s: String) -> HotkeyMatcher?
    public static let escapeKeyCode: UInt16 = 53
}

public final class HotkeyMonitor {
    public init(matcher: HotkeyMatcher, onPress: @escaping () -> Void,
                onRelease: @escaping () -> Void, onEscape: @escaping () -> Void)
    public func start() throws          // throws if the tap cannot be created
    public func stop()
    public var isRunning: Bool { get }
}

public enum HotkeyError: Error { case tapCreationFailed }
```

**Non-negotiable implementation rules:**
- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, ...)`. **`.listenOnly` is mandatory** — see Global Constraints.
- Event mask: `flagsChanged | keyDown | keyUp`.
- The callback **must** handle `.tapDisabledByTimeout` and `.tapDisabledByUserInput` by calling `CGEvent.tapEnable(tap:enable:true)` and returning. Without this the hotkey silently dies after a slow transcription.
- `fn` is detected as `event.flags.contains(.maskSecondaryFn)`; press/release are edges of that flag across successive `flagsChanged` events, so the monitor keeps the previous flag state.
- The C callback cannot capture context, so pass an `Unmanaged<HotkeyMonitor>` through `userInfo` and bridge back inside.
- Escape is `keyDown` with keycode 53 — reported, never consumed.

Tap creation needs Input Monitoring, so `HotkeyMonitor` itself is on the README manual checklist. `HotkeyConfig` parsing is tested here.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import WhisperFlowCore

@Suite("HotkeyConfig") struct HotkeyConfigTests {
    @Test("parses fn") func fn() {
        #expect(HotkeyConfig.parse("fn") == .modifierFlag(.maskSecondaryFn))
    }
    @Test("parses right option, case and spacing insensitive") func rightOption() {
        #expect(HotkeyConfig.parse("rightOption") == .modifierFlag(.maskAlternate))
        #expect(HotkeyConfig.parse("  RIGHT OPTION ") == .modifierFlag(.maskAlternate))
    }
    @Test("parses a modifier plus letter combination") func combo() {
        #expect(HotkeyConfig.parse("cmd+shift+d")
                == .keyCode(2, modifiers: [.maskCommand, .maskShift]))
    }
    @Test("rejects nonsense") func invalid() {
        #expect(HotkeyConfig.parse("") == nil)
        #expect(HotkeyConfig.parse("banana+z9") == nil)
    }
    @Test("escape keycode is 53") func escape() {
        #expect(HotkeyConfig.escapeKeyCode == 53)
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run tests** — PASS, 5 tests.
- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/Input Tests/WhisperFlowTests/HotkeyConfigTests.swift
git commit -m "feat: listen-only event tap and hotkey parsing"
```

---

## Task 12: The floating pill

**Files:**
- Create: `Sources/WhisperFlowCore/UI/PillView.swift`
- Create: `Sources/WhisperFlowCore/UI/PillWindow.swift`
- Test: `Tests/WhisperFlowTests/PillLabelTests.swift`

**Interfaces:**
```swift
@MainActor public final class PillWindow {
    public init()
    public func show(state: DictationState, level: Double, remaining: Duration?)
    public func update(state: DictationState, level: Double, remaining: Duration?)
    public func hide()
}

public enum PillLabel {
    public static func text(for state: DictationState) -> String
    public static func countdown(_ remaining: Duration) -> String?   // nil above 60s
}
```

**Window configuration — every line matters:**
```swift
let panel = NSPanel(contentRect: rect,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.level = .statusBar
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.ignoresMouseEvents = true
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
```
Plus an `NSPanel` subclass overriding `canBecomeKey` and `canBecomeMain` to `false`.
**This is load-bearing:** a panel that takes focus would redirect the Cmd-V to the pill's own app instead of the app being dictated into. Position bottom-centre of `NSScreen.main`, 120 pt above the bottom edge.

`PillView` is a SwiftUI view in an `NSHostingView`: a capsule with a mic glyph, the mode label, a 20-bar level meter driven by `level`, elapsed time, and the countdown when present.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import WhisperFlowCore

@Suite("PillLabel") struct PillLabelTests {
    let t0 = ContinuousClock().now

    @Test("labels name the mode and stage") func labels() {
        #expect(PillLabel.text(for: .recording(mode: .pushToTalk, startedAt: t0)) == "Recording")
        #expect(PillLabel.text(for: .recording(mode: .handsFree, startedAt: t0)) == "Hands-free")
        #expect(PillLabel.text(for: .transcribing) == "Transcribing…")
        #expect(PillLabel.text(for: .cleaning) == "Cleaning up…")
        #expect(PillLabel.text(for: .error("no mic")) == "no mic")
    }

    @Test("countdown appears only under a minute") func countdown() {
        #expect(PillLabel.countdown(.seconds(90)) == nil)
        #expect(PillLabel.countdown(.seconds(59)) == "0:59")
        #expect(PillLabel.countdown(.seconds(5)) == "0:05")
        #expect(PillLabel.countdown(.seconds(0)) == "0:00")
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run tests** — PASS, 2 tests.
- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/UI Tests/WhisperFlowTests/PillLabelTests.swift
git commit -m "feat: non-activating floating recording pill"
```

---

## Task 13: Menu bar, permissions, and launch at login

**Files:**
- Create: `Sources/WhisperFlowCore/UI/MenuBarController.swift`
- Create: `Sources/WhisperFlowCore/System/Permissions.swift`
- Test: `Tests/WhisperFlowTests/PermissionsTests.swift`

**Interfaces:**
```swift
public struct PermissionStatus: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let microphone: Bool
    public var allGranted: Bool { accessibility && inputMonitoring && microphone }
    public var missing: [String] { get }
}

public enum Permissions {
    public static func current() -> PermissionStatus
    public static func requestAccessibilityPrompt()
    public static func openSettings(for pane: SettingsPane)
    public enum SettingsPane: String { case accessibility, inputMonitoring, microphone }
}

@MainActor public final class MenuBarController {
    public init(controller: DictationController, config: Config)
    public func refresh(state: DictationState, permissions: PermissionStatus)
}
```

- `accessibility` → `AXIsProcessTrusted()`
- `inputMonitoring` → `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted`
- `microphone` → `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`
- Settings deep links: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (and `Privacy_ListenEvent`, `Privacy_Microphone`)
- Login item: `SMAppService.mainApp.register()` / `.unregister()`, with the checkbox reflecting `SMAppService.mainApp.status == .enabled`.

Menu items: **Enabled** (checkbox), current state, a warning row per missing permission that opens the right pane, **Launch at Login** (checkbox), **Open Config File**, **Reveal Logs**, **Quit**.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import WhisperFlowCore

@Suite("Permissions") struct PermissionsTests {
    @Test("missing lists exactly what is not granted") func missing() {
        let s = PermissionStatus(accessibility: false, inputMonitoring: true, microphone: false)
        #expect(s.missing == ["Accessibility", "Microphone"])
        #expect(!s.allGranted)
    }
    @Test("all granted has an empty missing list") func granted() {
        let s = PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true)
        #expect(s.missing.isEmpty)
        #expect(s.allGranted)
    }
    @Test("each pane maps to a settings url") func urls() {
        #expect(Permissions.SettingsPane.accessibility.rawValue == "accessibility")
        for p in [Permissions.SettingsPane.accessibility, .inputMonitoring, .microphone] {
            #expect(Permissions.settingsURL(for: p).scheme == "x-apple.systempreferences")
        }
    }
    @Test("current() runs without crashing in a test process") func current() {
        _ = Permissions.current()
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run tests** — PASS, 4 tests.
- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/UI/MenuBarController.swift Sources/WhisperFlowCore/System/Permissions.swift Tests/WhisperFlowTests/PermissionsTests.swift
git commit -m "feat: menu bar, permission checks, and launch at login"
```

---

## Task 14: App bundle, wiring, and the Makefile

**Files:**
- Create: `Sources/WhisperFlow/main.swift`, `Sources/WhisperFlow/AppDelegate.swift`
- Create: `Resources/Info.plist`, `Makefile`
- Create: `Sources/WhisperFlowCore/Config/ConfigWatcher.swift`

**`AppDelegate` responsibilities, in order:**
1. Load `.env`, then config — running `FirstRunSetup` and writing a config if none exists.
2. Build the object graph from config: recorder, engine, cleanup provider, inserter, logger.
3. Construct `DictationController`, `PillWindow`, `MenuBarController`.
4. Build a `TapPattern` from config timings; wire `HotkeyMonitor`'s three callbacks into it, then feed each `TapOutcome` to the controller.
5. Own the pending-tap timer (fires `pendingExpired`), the 5-minute session timer, and a display-link-ish 30 Hz timer that pushes `recorder.level` into the pill while recording.
6. Start `ConfigWatcher` (a `DispatchSource.makeFileSystemObjectSource` on the config file) and rebuild engine/cleanup/tap-pattern on change.

**`Info.plist` required keys:**
```xml
<key>CFBundleIdentifier</key><string>com.welaghil.whisperflow</string>
<key>CFBundleName</key><string>WhisperFlow</string>
<key>CFBundleExecutable</key><string>WhisperFlow</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key>
<string>WhisperFlow records your voice while you hold the dictation hotkey.</string>
```
`LSUIElement` keeps it out of the Dock and the app switcher.

**Makefile targets:**
```make
SIGN_IDENTITY ?= -
APP = build/WhisperFlow.app

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/WhisperFlow $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	codesign --force --deep --sign "$(SIGN_IDENTITY)" \
	  --options runtime --entitlements Resources/WhisperFlow.entitlements $(APP)

install: bundle
	rm -rf /Applications/WhisperFlow.app
	cp -R $(APP) /Applications/
	@echo "Installed. Launch with: open /Applications/WhisperFlow.app"

test:
	swift test

.PHONY: build bundle install test
```

**Code signing note that must land in the README:** TCC grants bind to the code signature. With the default ad-hoc identity (`-`) the signature changes on every rebuild, so Accessibility and Input Monitoring must be re-granted each time. Creating a self-signed certificate once and passing `SIGN_IDENTITY="WhisperFlow Dev"` makes grants persist.

- [ ] **Step 1: Write `Info.plist`, entitlements, and the `Makefile`.**
- [ ] **Step 2: Write `ConfigWatcher` plus a test that a write to the watched file fires the callback within 2 seconds.**
- [ ] **Step 3: Write `main.swift` and `AppDelegate.swift` wiring the graph above.**
- [ ] **Step 4: Build and bundle**

Run: `make bundle`
Expected: `build/WhisperFlow.app` exists and `codesign -dv build/WhisperFlow.app` reports a valid signature.

- [ ] **Step 5: Verify it launches and shows a menu bar item**

Run: `open build/WhisperFlow.app` then `pgrep -f WhisperFlow`
Expected: a PID, a menu bar icon, and **no Dock icon**.

- [ ] **Step 6: Commit**

```bash
git add Sources/WhisperFlow Resources Makefile Sources/WhisperFlowCore/Config/ConfigWatcher.swift
git commit -m "feat: app bundle, object graph wiring, and build tooling"
```

---

## Task 15: README and manual verification

**Files:** Create `README.md`, `.env.example`

**README must contain, in this order:**

1. **What it is / what it does not do** — no accounts, no telemetry, offline-capable.
2. **Install** — `brew install whisper-cpp`, model download, `make install`.
   Include the one-time shader warm-up (`whisper-cli --help` takes ~30 s the first time) so the first dictation is not mistaken for a hang.
3. **Permissions — the section the user asked for.** For each of the three, state the exact pane, why it is needed, and what breaks without it:
   - **Microphone** — System Settings → Privacy & Security → Microphone. Needed to record. Prompted automatically on first use.
   - **Input Monitoring** — System Settings → Privacy & Security → Input Monitoring. Needed for the `CGEventTap` that watches the hotkey and Esc. Without it the hotkey does nothing. **Not** prompted automatically — must be added by hand with the `+` button.
   - **Accessibility** — System Settings → Privacy & Security → Accessibility. Needed to synthesize Cmd-V. Without it text lands on the clipboard but is not pasted.
   - State plainly that the app never consumes keystrokes, so Esc always still reaches the focused app.
4. **Required macOS setting** — System Settings → Keyboard → "Press fn key to" → **Do Nothing**, or macOS fires its own emoji/dictation behaviour alongside the hotkey.
5. **Configuration reference** — every key in `config.json` with its type, default, and effect. Document `output.restorePreviousClipboard` together with its race caveat.
6. **Choosing a cleanup provider** — the cost/latency/offline table, including that ChatGPT and Claude subscriptions do **not** grant API access.
7. **Manual verification checklist** — the permission-gated paths that have no automated coverage:
   - [ ] Hold `fn` in TextEdit, speak, release → cleaned text appears at the cursor
   - [ ] The pill appears while recording and shows a moving level meter
   - [ ] Focus does not leave TextEdit while the pill is visible (the caret keeps blinking)
   - [ ] Double-tap `fn` → pill reads "Hands-free"; a single tap ends it and inserts
   - [ ] A hands-free session left running auto-stops at 5 minutes
   - [ ] `Esc` during recording discards; nothing is pasted
   - [ ] `Esc` during transcription aborts it; `pgrep whisper-cli` returns nothing
   - [ ] `Esc` still dismisses a Safari dialog while the app is running (proves listen-only)
   - [ ] Transcript remains on the clipboard; Cmd-V pastes it again
   - [ ] With `restorePreviousClipboard: true`, the prior clipboard returns
   - [ ] Menu bar toggle off → hotkey inert
   - [ ] Launch at Login survives a reboot
   - [ ] With Wi-Fi off and `whispercpp` + `ollama`/`off`, dictation still works
8. **Troubleshooting** — hotkey dead after a long transcription (tap re-arm), permissions lost after rebuild (code signing), `whisper-cli` not found, Ollama not running.

- [ ] **Step 1: Write `README.md` and `.env.example`.**
- [ ] **Step 2: Walk the manual checklist end to end and fix what fails.**
- [ ] **Step 3: Run the full suite** — `swift test` → all tests pass.
- [ ] **Step 4: Commit**

```bash
git add README.md .env.example
git commit -m "docs: setup, permissions, configuration, and verification checklist"
```

---

## Self-Review Notes

**Spec coverage:** every numbered success criterion maps to a task —
(1) Tasks 4/5/9/10, (2) Tasks 2/10, (3) Task 10 + 14 timer, (4) Tasks 10/11,
(5) Tasks 5/7/8, (6) Global Constraints + Task 15.
Spec §5.1–5.9 map to Tasks 11, 4, 5–6, 7, 8, 9, 12, 1, 13 respectively.
Spec §6 error table is covered by Task 10's tests plus Task 13's permission rows.
Spec §8 build/signing is Task 14.

**Type consistency:** `TapOutcome` (Task 2) is consumed unchanged by `DictationController.handle` (Task 10) and produced by `HotkeyMonitor` callbacks (Task 11). `TranscriptionEngine` (Task 5) is implemented by `WhisperAPIEngine` (Task 6). `CleanupProvider` (Task 7) is faked in Task 10. `DictationState` (Task 10) is consumed by `PillLabel` (Task 12) and `MenuBarController` (Task 13). `Config`/`EngineKind`/`CleanupKind` (Task 1) are used by Tasks 5–8 and 14. No orphan types.

**Known gap, accepted deliberately:** `AudioRecorder`'s AVAudioEngine path, `HotkeyMonitor`'s tap, `TextInserter`'s synthetic Cmd-V, and `PillWindow`'s focus behaviour have no automated tests — all four need TCC grants and live hardware. They are covered by the Task 15 checklist instead of fabricated coverage.
