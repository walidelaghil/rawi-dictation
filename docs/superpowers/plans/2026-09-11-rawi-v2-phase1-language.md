# Rawi v2 · Phase 1 — Language Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One hotkey that handles English, Arabic and both mixed — replacing the English-only path that today does not degrade on Arabic, it fails.

**Architecture:** A single transcription model (`large-v3-turbo-q5_0`) always run with `-l auto`, so language detection is free as part of transcribing. Cleanup is then routed by the *script of the resulting transcript* — a deterministic, zero-cost check with no model involved — because the fast cleanup model silently translates Arabic into English. A `ModelStore` owns model paths, presence and download. None of this is user-configurable: the seam that v1 exposed as two hotkeys disappears.

**Tech Stack:** Swift 6.3, SwiftPM, `whisper-cli` (Homebrew `whisper-cpp`), Ollama.

## Global Constraints

- Deployment target **macOS 14.0**; Swift tools **6.0**; strict concurrency.
- **Zero third-party Swift dependencies.**
- No telemetry, no analytics, no account. Fully functional offline.
- Every task ends green: `swift build` and `swift test` both succeed before the commit.
- Do **not** rename `WhisperCppEngine`, `WhisperAPIEngine`, `whisper-cli` or the `whispercpp` config key — they name upstream whisper.cpp, not this product.
- Existing behaviour that must not regress: the listen-only event tap, `CleanupGuard`, the Carbon hotkey fallback, and the clipboard-plus-⌘V insertion path.
- **Commands / speech-to-action is out of scope** — no menu item, no nav entry, no config key. See `docs/BACKLOG.md`.
- The user's live config is at `~/.config/rawi/config.json`; migrations must not destroy it.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/RawiCore/Transcribe/ScriptDetector.swift` | **Create.** Decide whether a transcript is Arabic-script |
| `Sources/RawiCore/Cleanup/RoutedCleanup.swift` | **Create.** Pick the cleanup model by script, delegate to `ChatCleanup` |
| `Sources/RawiCore/Models/ModelStore.swift` | **Create.** Known models, presence on disk, resolved paths, download |
| `Sources/RawiCore/Config/Config.swift` | **Modify.** `cleanup.model` → `cleanup.models`; whispercpp language default `auto` |
| `Sources/RawiCore/Cleanup/CleanupProvider.swift` | **Modify.** Factory returns `RoutedCleanup` for local providers |
| `Sources/RawiCore/Config/FirstRunSetup.swift` | **Modify.** Detect the turbo model; default to it |
| `Sources/Rawi/Doctor.swift` | **Modify.** Report the routed models and model presence |
| `Tests/RawiTests/ScriptDetectorTests.swift` | **Create.** |
| `Tests/RawiTests/RoutedCleanupTests.swift` | **Create.** |
| `Tests/RawiTests/ModelStoreTests.swift` | **Create.** |

---

## Task 1: Script detection

The whole routing decision rests on this, and it must never call a model.

**Files:**
- Create: `Sources/RawiCore/Transcribe/ScriptDetector.swift`
- Test: `Tests/RawiTests/ScriptDetectorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
```swift
public enum Script: String, Sendable, Equatable { case latin, arabic }

public enum ScriptDetector {
    /// Arabic when Arabic-script letters are at least `threshold` of the letters present.
    public static func detect(_ text: String, threshold: Double = 0.15) -> Script
    public static func arabicRatio(_ text: String) -> Double
}
```

**Why a ratio and not "contains any Arabic":** a mixed sentence is the normal case
here — `"يعني الـ API مو شغال، لازم نسوي deploy"` is mostly Arabic with Latin
technical terms, and must route to the Arabic-capable model. Conversely an English
sentence quoting a single Arabic word must not. 15% of letters is the boundary.

- [x] **Step 1: Write the failing tests**

```swift
import Testing
@testable import RawiCore

@Suite("ScriptDetector") struct ScriptDetectorTests {
    @Test("pure english is latin") func english() {
        #expect(ScriptDetector.detect("So I think we should ship on Friday.") == .latin)
    }

    @Test("pure arabic is arabic") func arabic() {
        #expect(ScriptDetector.detect("يعني أعتقد أنه لازم نأجل الاجتماع") == .arabic)
    }

    @Test("arabic with latin technical terms routes as arabic") func mixed() {
        // The normal bilingual case: mostly Arabic, English jargon left in Latin.
        #expect(ScriptDetector.detect("يعني الـ API مو شغال، لازم نسوي deploy مرة ثانية") == .arabic)
    }

    @Test("english quoting one arabic word stays latin") func mostlyLatin() {
        #expect(ScriptDetector.detect("The Arabic word for narrator is راوي and it suits the app well enough") == .latin)
    }

    @Test("digits and punctuation do not sway the ratio") func nonLetters() {
        #expect(ScriptDetector.detect("12:30 — 45% (!!) يعني تمام كذا") == .arabic)
        #expect(ScriptDetector.detect("12:30 — 45% (!!) deploy to staging now") == .latin)
    }

    @Test("empty and whitespace are latin, never a crash") func empty() {
        #expect(ScriptDetector.detect("") == .latin)
        #expect(ScriptDetector.detect("   \n  ") == .latin)
        #expect(ScriptDetector.arabicRatio("") == 0)
    }

    @Test("ratio is a fraction of letters, not of characters") func ratio() {
        #expect(abs(ScriptDetector.arabicRatio("abcd راوي") - 0.5) < 0.01)
    }

    @Test("arabic-presentation and extended ranges count as arabic") func ranges() {
        #expect(ScriptDetector.detect("ﷺ ﷻ ﷲ") == .arabic)   // U+FDF0–FDFF
        #expect(ScriptDetector.detect("پژگ چ") == .arabic)      // U+0698 etc.
    }

    @Test("the threshold is honoured") func threshold() {
        let s = "one two three راوي"
        #expect(ScriptDetector.detect(s, threshold: 0.9) == .latin)
        #expect(ScriptDetector.detect(s, threshold: 0.05) == .arabic)
    }
}
```

- [x] **Step 2: Run to verify failure**

Run: `swift test --filter ScriptDetectorTests`
Expected: FAIL — `ScriptDetector` not found.

- [x] **Step 3: Implement**

Count letters with `Character.isLetter`; count as Arabic any scalar in
`0x0600–0x06FF`, `0x0750–0x077F`, `0x08A0–0x08FF`, `0xFB50–0xFDFF`, `0xFE70–0xFEFF`.
Return `.latin` when there are no letters at all.

- [x] **Step 4: Run to verify pass** — `swift test --filter ScriptDetectorTests` → PASS, 9 tests.

- [x] **Step 5: Commit**

```bash
git add Sources/RawiCore/Transcribe/ScriptDetector.swift Tests/RawiTests/ScriptDetectorTests.swift
git commit -m "feat: detect Arabic script to route cleanup"
```

---

## Task 2: Config — cleanup models per script

**Files:**
- Modify: `Sources/RawiCore/Config/Config.swift`
- Test: `Tests/RawiTests/ConfigTests.swift`

**Interfaces:**
- Consumes: `Script` (Task 1).
- Produces:
```swift
public struct CleanupModels: Codable, Sendable, Equatable {
    public var latin: String     // default "qwen2.5:1.5b"
    public var arabic: String    // default "qwen2.5:3b"
    public init(latin: String, arabic: String)
    public func model(for script: Script) -> String
}

// CleanupSettings gains:
public var models: CleanupModels
// `model` is REMOVED.
```
`WhisperCppSettings.language` default changes from `"en"` to `"auto"`, and
`Config.defaultWhisperCpp.model` now points at `ggml-large-v3-turbo-q5_0.bin`.

**Migration:** a config written by v1 carries `cleanup.model` and no
`cleanup.models`. Decoding must not fail. Map the old single value onto `latin`,
leave `arabic` at its default, and drop the old key on the next save.

- [x] **Step 1: Write the failing tests** (append to `ConfigTests.swift`)

```swift
@Suite("Cleanup models") struct CleanupModelsTests {
    @Test("defaults are the measured winners per script") func defaults() {
        let m = Config.default.cleanup.models
        #expect(m.latin == "qwen2.5:1.5b")
        #expect(m.arabic == "qwen2.5:3b")
        #expect(m.model(for: .latin) == "qwen2.5:1.5b")
        #expect(m.model(for: .arabic) == "qwen2.5:3b")
    }

    @Test("whisper now runs with automatic language detection") func autoLang() {
        #expect(Config.default.whispercpp.language == "auto")
        #expect(Config.default.whispercpp.model.contains("large-v3-turbo"))
    }

    @Test("a v1 config carrying cleanup.model still loads") func migratesOldKey() throws {
        let json = #"{"cleanup":{"provider":"ollama","model":"qwen2.5:1.5b"}}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.cleanup.models.latin == "qwen2.5:1.5b")
        #expect(c.cleanup.models.arabic == "qwen2.5:3b")
    }

    @Test("an explicit models block wins over the legacy key") func explicitWins() throws {
        let json = #"{"cleanup":{"model":"old","models":{"latin":"a","arabic":"b"}}}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.cleanup.models.latin == "a")
        #expect(c.cleanup.models.arabic == "b")
    }

    @Test("saving drops the legacy key") func saveDropsLegacy() throws {
        let json = #"{"cleanup":{"model":"qwen2.5:1.5b"}}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-\(UUID().uuidString).json")
        try c.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("\"model\" :"))
        #expect(text.contains("\"models\""))
    }
}
```

- [x] **Step 2: Run to verify failure** — `swift test --filter "Cleanup models"` → FAIL.

- [x] **Step 3: Implement.** Add `CleanupModels`. In `CleanupSettings.init(from:)`,
decode `models` if present; otherwise build one from a legacy `model` string;
otherwise use defaults. Give `CleanupSettings` an explicit `encode(to:)` that emits
`provider`, `models`, `prompt` and never `model`.

- [x] **Step 4: Run tests** — PASS, 5 new tests; whole suite still green.

- [x] **Step 5: Commit**

```bash
git add Sources/RawiCore/Config/Config.swift Tests/RawiTests/ConfigTests.swift
git commit -m "feat: per-script cleanup models, with migration from the v1 key"
```

---

## Task 3: Routed cleanup

**Files:**
- Create: `Sources/RawiCore/Cleanup/RoutedCleanup.swift`
- Modify: `Sources/RawiCore/Cleanup/CleanupProvider.swift`
- Test: `Tests/RawiTests/RoutedCleanupTests.swift`

**Interfaces:**
- Consumes: `ScriptDetector.detect(_:threshold:)`, `CleanupModels.model(for:)`,
  `ChatCleanup(kind:apiKey:model:prompt:session:)`, `CleanupProvider`.
- Produces:
```swift
public final class RoutedCleanup: CleanupProvider {
    public init(kind: CleanupKind, apiKey: String?, models: CleanupModels,
                prompt: String, makeProvider: ((String) -> any CleanupProvider)? = nil)
    /// The model chosen for a given transcript. Exposed for logging and tests.
    public func model(for transcript: String) -> String
}
```
`CleanupProviderFactory.make(config:env:)` returns a `RoutedCleanup` for `.ollama`,
`.openai` and `.anthropic`, and `NoopCleanup` for `.off`. `defaultModel(for:)` is
replaced by `defaultModels(for:) -> CleanupModels`.

**Why route inside a provider rather than at the controller:** the controller
already has one `CleanupProvider` and should not learn about scripts. Routing is a
property of cleanup, so it stays behind the protocol.

**Cancellation:** `cancel()` must cancel whichever child is in flight — a route
decided per call means the provider cannot assume which one that is.

- [x] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import RawiCore

final class SpyCleanup: CleanupProvider, @unchecked Sendable {
    let name: String
    var calls: [String] = []
    var cancels = 0
    var result: Result<String, any Error> = .success("cleaned")
    init(name: String) { self.name = name }
    func clean(_ t: String) async throws -> String { calls.append(t); return try result.get() }
    func cancel() { cancels += 1 }
}

@Suite("RoutedCleanup") struct RoutedCleanupTests {
    let models = CleanupModels(latin: "small-model", arabic: "big-model")

    func rig() -> (RoutedCleanup, [String: SpyCleanup]) {
        let spies = ["small-model": SpyCleanup(name: "small-model"),
                     "big-model": SpyCleanup(name: "big-model")]
        let r = RoutedCleanup(kind: .ollama, apiKey: nil, models: models, prompt: "P",
                              makeProvider: { spies[$0]! })
        return (r, spies)
    }

    @Test("english goes to the small model") func english() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("ship the release on Friday")
        #expect(spies["small-model"]!.calls.count == 1)
        #expect(spies["big-model"]!.calls.isEmpty)
    }

    @Test("arabic goes to the arabic-capable model") func arabic() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("يعني أعتقد أنه لازم نأجل الاجتماع")
        #expect(spies["big-model"]!.calls.count == 1)
        #expect(spies["small-model"]!.calls.isEmpty)
    }

    @Test("mixed arabic and english goes to the arabic model") func mixed() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("يعني الـ API مو شغال، لازم نسوي deploy")
        #expect(spies["big-model"]!.calls.count == 1)
    }

    @Test("the chosen model is inspectable without running it") func choice() {
        let (r, _) = rig()
        #expect(r.model(for: "hello there") == "small-model")
        #expect(r.model(for: "مرحبا كيف حالك") == "big-model")
    }

    @Test("a provider is built once per model and reused") func reuse() async throws {
        var built: [String] = []
        let spies = ["small-model": SpyCleanup(name: "s"), "big-model": SpyCleanup(name: "b")]
        let r = RoutedCleanup(kind: .ollama, apiKey: nil, models: models, prompt: "P",
                              makeProvider: { built.append($0); return spies[$0]! })
        _ = try await r.clean("one two three")
        _ = try await r.clean("four five six")
        #expect(built == ["small-model"])
    }

    @Test("cancel reaches whichever child ran") func cancels() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("يعني تمام")
        r.cancel()
        #expect(spies["big-model"]!.cancels == 1)
        #expect(spies["small-model"]!.cancels == 0)
    }

    @Test("an empty transcript is returned without building anything") func empty() async throws {
        var built = 0
        let r = RoutedCleanup(kind: .ollama, apiKey: nil, models: models, prompt: "P",
                              makeProvider: { _ in built += 1; return SpyCleanup(name: "x") })
        #expect(try await r.clean("   ") == "   ")
        #expect(built == 0)
    }

    @Test("the factory returns a routed provider for every live kind") func factory() throws {
        var c = Config.default
        c.cleanup.provider = .ollama
        #expect(try CleanupProviderFactory.make(config: c, env: DotEnv(contents: "")) is RoutedCleanup)
        c.cleanup.provider = .off
        #expect(try CleanupProviderFactory.make(config: c, env: DotEnv(contents: "")) is NoopCleanup)
    }
}
```

- [x] **Step 2: Run to verify failure** — `swift test --filter RoutedCleanup` → FAIL.

- [x] **Step 3: Implement** `RoutedCleanup` with an `NSLock`-guarded cache of
built providers keyed by model name, plus a `lastUsed` reference for `cancel()`.
Default `makeProvider` builds a `ChatCleanup` with the given kind, key and prompt.

- [x] **Step 4: Run tests** — PASS, 8 tests.

- [x] **Step 5: Commit**

```bash
git add Sources/RawiCore/Cleanup Tests/RawiTests/RoutedCleanupTests.swift
git commit -m "feat: route cleanup to a model that will not translate Arabic"
```

---

## Task 4: Model store

**Files:**
- Create: `Sources/RawiCore/Models/ModelStore.swift`
- Test: `Tests/RawiTests/ModelStoreTests.swift`

**Interfaces:**
```swift
public struct WhisperModel: Sendable, Equatable, Identifiable {
    public let id: String          // "large-v3-turbo-q5_0"
    public let filename: String    // "ggml-large-v3-turbo-q5_0.bin"
    public let displayName: String
    public let approxBytes: Int
    public let multilingual: Bool
    public var downloadURL: URL { get }
}

public enum ModelStore {
    public static let known: [WhisperModel]
    public static var directory: URL                     // …/Application Support/Rawi/models
    public static func url(for model: WhisperModel) -> URL
    public static func isInstalled(_ model: WhisperModel) -> Bool
    public static func installed() -> [WhisperModel]
    public static func model(id: String) -> WhisperModel?
    /// The model a config points at, if it is one we know.
    public static func model(forPath path: String) -> WhisperModel?
    public static let recommended: WhisperModel          // large-v3-turbo-q5_0
    public static func download(_ model: WhisperModel,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}
```

Known models, with the sizes measured on disk: `large-v3-turbo-q5_0` (547 MB,
multilingual, **recommended**), `small.en` (465 MB, English only),
`base.en` (148 MB, English only), `medium` (1.5 GB, multilingual).

Downloads come from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<filename>`.
Write to a `.partial` file and move into place only on success, so an interrupted
download can never masquerade as an installed model.

- [x] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import RawiCore

@Suite("ModelStore") struct ModelStoreTests {
    @Test("the recommended model is multilingual") func recommended() {
        // English-only was the v1 bug: it did not degrade on Arabic, it failed.
        #expect(ModelStore.recommended.multilingual)
        #expect(ModelStore.recommended.id == "large-v3-turbo-q5_0")
    }

    @Test("every known model has a plausible download url") func urls() {
        for m in ModelStore.known {
            #expect(m.downloadURL.absoluteString.hasSuffix(m.filename))
            #expect(m.downloadURL.host == "huggingface.co")
            #expect(m.approxBytes > 1_000_000)
        }
    }

    @Test("ids are unique and filenames are unique") func unique() {
        #expect(Set(ModelStore.known.map(\.id)).count == ModelStore.known.count)
        #expect(Set(ModelStore.known.map(\.filename)).count == ModelStore.known.count)
    }

    @Test("English-only models are flagged as such") func englishOnly() {
        #expect(ModelStore.model(id: "small.en")?.multilingual == false)
        #expect(ModelStore.model(id: "base.en")?.multilingual == false)
    }

    @Test("a model resolves from a configured path") func fromPath() {
        let p = "/Users/x/Library/Application Support/Rawi/models/ggml-small.en.bin"
        #expect(ModelStore.model(forPath: p)?.id == "small.en")
        #expect(ModelStore.model(forPath: "/tmp/mystery.bin") == nil)
    }

    @Test("an unknown id is nil rather than a crash") func unknown() {
        #expect(ModelStore.model(id: "not-a-model") == nil)
    }

    @Test("installed reflects what is actually on disk") func installed() {
        // Whatever this machine has, the two answers must agree.
        for m in ModelStore.known {
            let onDisk = FileManager.default.fileExists(atPath: ModelStore.url(for: m).path)
            #expect(ModelStore.isInstalled(m) == onDisk)
        }
        #expect(Set(ModelStore.installed().map(\.id))
                == Set(ModelStore.known.filter(ModelStore.isInstalled).map(\.id)))
    }

    @Test("the directory sits under Application Support, not the config dir") func dir() {
        #expect(ModelStore.directory.path.contains("Application Support/Rawi/models"))
    }
}
```

- [x] **Step 2: Run to verify failure** — `swift test --filter ModelStore` → FAIL.
- [x] **Step 3: Implement.** `download` uses `URLSession.bytes(for:)` to stream and
report progress against `expectedContentLength`.
- [x] **Step 4: Run tests** — PASS, 8 tests.
- [x] **Step 5: Commit**

```bash
git add Sources/RawiCore/Models Tests/RawiTests/ModelStoreTests.swift
git commit -m "feat: model store with presence, paths and resumable-safe download"
```

---

## Task 5: Wire it up and prove it end to end

**Files:**
- Modify: `Sources/RawiCore/Config/FirstRunSetup.swift`
- Modify: `Sources/Rawi/Doctor.swift`
- Modify: `Sources/Rawi/AppDelegate.swift`
- Test: `Tests/RawiTests/FirstRunSetupTests.swift`, `Tests/RawiTests/LanguageEndToEndTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `Probes` gains `turboModelFound: Bool`; `FirstRunSetup.detect` selects
  `.whispercpp` only when the **multilingual** model is present.

- [x] **Step 1: Update first-run detection tests**

```swift
@Test("local engine requires the multilingual model, not just any model") func needsTurbo() {
    let p = Probes(envKeys: [], ollamaReachable: false,
                   whisperBinaryFound: true, whisperModelFound: true, turboModelFound: false)
    // small.en alone is not enough: it cannot do Arabic at all.
    #expect(FirstRunSetup.detect(p).engine != .whispercpp || FirstRunSetup.detect(p).needsModelDownload)
}

@Test("with the turbo model present, local is chosen and language is auto") func turboPresent() {
    let p = Probes(envKeys: [], ollamaReachable: true,
                   whisperBinaryFound: true, whisperModelFound: true, turboModelFound: true)
    let c = FirstRunSetup.detect(p)
    #expect(c.engine == .whispercpp)
    #expect(c.whispercpp.language == "auto")
    #expect(c.whispercpp.model.contains("large-v3-turbo"))
}
```

Add `public var needsModelDownload: Bool` to `Config` as a computed property:
`engine == .whispercpp && ModelStore.model(forPath: whispercpp.model).map { !ModelStore.isInstalled($0) } ?? true`.

- [x] **Step 2: Write the end-to-end test** (skipped when the model is absent)

```swift
import Testing
import Foundation
@testable import RawiCore

/// Proves the real pipeline handles both languages through ONE configuration.
@Suite("Language end to end") struct LanguageEndToEndTests {
    static var ready: Bool {
        ModelStore.isInstalled(ModelStore.recommended)
            && WhisperCppEngine.resolveBinary("whisper-cli") != nil
    }

    func engine() -> WhisperCppEngine {
        WhisperCppEngine(binary: "whisper-cli",
                         model: ModelStore.url(for: ModelStore.recommended).path,
                         language: "auto", threads: 8)
    }

    func say(_ text: String, voice: String?) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-e2e-\(UUID().uuidString).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args = ["-o", url.path, "--data-format=LEI16@16000"]
        if let voice { args += ["-v", voice] }
        args.append(text)
        p.arguments = args
        try p.run(); p.waitUntilExit()
        return url
    }

    @Test("one configuration transcribes English",
          .enabled(if: LanguageEndToEndTests.ready), .timeLimit(.minutes(2)))
    func english() async throws {
        let wav = try say("The deploy to staging finished successfully", voice: nil)
        defer { try? FileManager.default.removeItem(at: wav) }
        let text = try await engine().transcribe(wav: wav).lowercased()
        #expect(text.contains("deploy"))
        #expect(text.contains("staging"))
        #expect(ScriptDetector.detect(text) == .latin)
    }

    @Test("the same configuration transcribes Arabic",
          .enabled(if: LanguageEndToEndTests.ready), .timeLimit(.minutes(2)))
    func arabic() async throws {
        let wav = try say("الاجتماع يوم الاثنين والتقرير غير جاهز", voice: "Majed")
        defer { try? FileManager.default.removeItem(at: wav) }
        let text = try await engine().transcribe(wav: wav)
        #expect(!text.isEmpty)
        // The v1 bug: this returned English or nothing. Now it must come back in Arabic.
        #expect(ScriptDetector.detect(text) == .arabic, "expected Arabic script, got: \(text)")
    }
}
```

- [x] **Step 3: Run both** — `swift test --filter "Language end to end"` → PASS, 2 tests.

- [x] **Step 4: Update `Doctor.swift`** to print the resolved transcription model
with its multilingual flag, and both cleanup models with the script each serves:

```
Local transcription
  [OK  ] whisper-cli       /opt/homebrew/bin/whisper-cli
  [OK  ] model             large-v3-turbo-q5_0 · multilingual · 547 MB
  language                 auto

Cleanup
  [OK  ] ollama            http://localhost:11434
  latin                    qwen2.5:1.5b
  arabic                   qwen2.5:3b
```

- [x] **Step 5: Update `AppDelegate`** — `makeCleanup` now returns the routed
provider, and the fallback when the local engine has no model logs which model to
download rather than failing silently.

- [x] **Step 6: Migrate the live config and verify by hand**

```bash
make install
~/Applications/Rawi.app/Contents/MacOS/Rawi --doctor
```
Expected: engine `whispercpp`, model `large-v3-turbo-q5_0`, language `auto`, and
both cleanup models listed. The existing `~/.config/rawi/config.json` must still
load — it carries the v1 `cleanup.model` key.

- [x] **Step 7: Full suite and commit**

```bash
swift test
git add -A
git commit -m "feat: one hotkey for English and Arabic via auto-detect and routed cleanup"
```

---

## Manual verification

Automated tests cannot hold the key or speak. After Task 5:

- [x] Hold `⌥Space`, speak English → correct text on the clipboard
- [x] Hold `⌥Space`, speak Arabic → **Arabic** text, not English, not empty
- [x] Speak a mixed sentence with English technical terms → both scripts survive
- [x] `~/Library/Logs/Rawi/rawi.log` shows the detected language and the cleanup model chosen
- [x] Round trip is ~2.8 s and feels acceptable in use
- [x] Deleting `~/.config/rawi/config.json` and relaunching writes a working config

---

## Self-Review Notes

**Spec coverage.** §2 language → Tasks 1, 3, 4, 5. §2 script-routed cleanup →
Tasks 1–3. Model management → Task 4. §8 phase 1 scope → all five tasks. §3 theme,
§4 surfaces, §5 destinations, §6 memory and §7 transforms are phases 2–6 and are
deliberately absent here.

**Type consistency.** `Script` (Task 1) is consumed by `CleanupModels.model(for:)`
(Task 2) and `RoutedCleanup` (Task 3). `CleanupModels` (Task 2) is consumed by
`RoutedCleanup.init` (Task 3) and `FirstRunSetup` (Task 5). `WhisperModel` and
`ModelStore` (Task 4) are consumed by `Config.needsModelDownload` and `Doctor`
(Task 5). No orphans.

**Known gap, accepted.** The end-to-end Arabic test uses `say -v Majed`, which
pronounces English words with Arabic phonetics — so it validates Arabic
transcription but **not** genuine code-switching. Real bilingual speech is on the
manual checklist because no synthetic voice can stand in for it.
