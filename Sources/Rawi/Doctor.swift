import AVFoundation
import AppKit
import Foundation
import RawiCore

/// `Rawi --doctor` prints everything needed to diagnose a setup problem
/// without guessing: permissions, resolved paths, and the active providers.
enum Doctor {
    static func run() async {
        let status = Permissions.current()
        print("Rawi doctor\n")

        print("Permissions")
        // Read from a shell, the two grants below are the shell's, not Rawi's.
        // macOS credits a binary a terminal started to that terminal, so
        // `AXIsProcessTrusted()` answers for whoever ran `make doctor` — and this
        // check, the one the README sends people to, reported both missing on a
        // Mac where the running app had both, then recommended a Karabiner
        // workaround nobody needed. Say so rather than print a confident no.
        let borrowed = launchedFromTerminal && !(status.inputMonitoring && status.accessibility)
        if borrowed {
            print("  Run from a terminal, so Input Monitoring and Accessibility below")
            print("  are this terminal's answer, not Rawi's — macOS credits them to")
            print("  whoever started the process.")
            print(appIsRunning
                ? "  Rawi is running. Its own answer is in the menu bar panel."
                : "  Open Rawi and look at the menu bar panel for its own answer.")
            print("")
        }
        line("Microphone", status.microphone,
             fix: "System Settings → Privacy & Security → Microphone")
        line("Input Monitoring", status.inputMonitoring, unknown: borrowed,
             fix: "System Settings → Privacy & Security → Input Monitoring (add with +)")
        line("Accessibility", status.accessibility, unknown: borrowed,
             fix: "System Settings → Privacy & Security → Accessibility (add with +)")

        print("\nConfiguration")
        let configExists = FileManager.default.fileExists(atPath: Config.configFile.path)
        line("config.json", configExists, detail: Config.configFile.path,
             fix: "will be created on first launch")

        let env = DotEnv.load(from: Config.envFile)
        let envExists = FileManager.default.fileExists(atPath: Config.envFile.path)
        line(".env", envExists, detail: envExists ? "keys: \(env.keys.sorted().joined(separator: ", "))"
                                                 : Config.envFile.path,
             fix: "optional — only needed for API providers")

        let config = (try? Config.load()) ?? .default
        let backend = config.hotkeyBackend.resolved(
            inputMonitoringGranted: status.inputMonitoring)
        print("  appearance        \(config.appearance.rawValue)")
        print("  hotkey            \(config.hotkey)")
        if borrowed {
            // Which backend runs, and therefore which key actually works, follows
            // from a grant this process cannot read. Printing the fallback here
            // told people to press a key they had not been using for days.
            print("  hotkey backend    depends on Input Monitoring, which this check cannot see")
        } else {
            print("  hotkey backend    \(backend.rawValue)"
                  + (backend == .carbon ? "  (no permissions needed)" : ""))
            if backend == .carbon {
                let effective = HotkeyConfig.isCarbonCompatible(config.hotkey)
                    ? config.hotkey : config.fallbackHotkey
                print("  → press           \(effective)")
                print("  → cancel with     \(config.cancelHotkey)")
                if effective != config.hotkey {
                    print("     (“\(config.hotkey)” needs Input Monitoring, so the fallback is used)")
                }
            }
        }
        print("  engine            \(config.engine.rawValue)")
        print("  cleanup           \(config.cleanup.provider.rawValue)")
        if config.cleanup.provider != .off {
            print("    latin           \(config.cleanup.models.latin)")
            print("    arabic          \(config.cleanup.models.arabic)")
        }
        print("  restore clipboard \(config.output.restorePreviousClipboard)")

        print("\nLocal transcription")
        let binary = WhisperCppEngine.resolveBinary(config.whispercpp.binary)
        line("whisper-cli", binary != nil, detail: binary?.path ?? "not found",
             fix: "brew install whisper-cpp")
        let modelPath = Config.expand(config.whispercpp.model)
        let modelExists = FileManager.default.fileExists(atPath: modelPath)
        let known = ModelStore.model(forPath: config.whispercpp.model)
        let detail = known.map {
            "\($0.id) · \($0.multilingual ? "multilingual" : "ENGLISH ONLY") · \($0.approxSize)"
        } ?? modelPath
        line("model", modelExists, detail: detail,
             fix: "run: rawi --download-model \(ModelStore.recommended.id)")
        print("  language          \(config.whispercpp.language)")
        if let known, !known.multilingual {
            print("           ↳ this model cannot transcribe Arabic at all.")
            print("             Switch to \(ModelStore.recommended.id) for one hotkey in both languages.")
        }

        print("\nCleanup provider")
        if config.cleanup.provider == .ollama {
            let reachable = await FirstRunSetup.isOllamaReachable(timeout: 1.0)
            line("ollama", reachable, detail: "http://localhost:11434",
                 fix: "brew install ollama && ollama serve && ollama pull "
                    + "\(config.cleanup.models.latin) && ollama pull \(config.cleanup.models.arabic)")
        } else if config.cleanup.provider == .off {
            print("  — disabled; the raw transcript is inserted as-is")
        } else {
            let key = config.cleanup.provider == .openai ? "OPENAI_API_KEY" : "ANTHROPIC_API_KEY"
            line(key, env[key]?.isEmpty == false, detail: "from \(Config.envFile.path)",
                 fix: "add \(key)=... to ~/.config/rawi/.env")
        }

        print("")
        if borrowed {
            print("Nothing below is judged on the two grants this terminal cannot see.")
        } else if status.allGranted {
            print("All permissions granted.")
        } else if !status.microphone {
            print("Microphone is required and not granted — nothing can be recorded.")
        } else {
            print("Running without: \(status.missing.joined(separator: ", "))")
            print("This is workable. What it means:")
            if !status.inputMonitoring {
                print("  · hotkey uses the permission-free Carbon backend")
                print("    (a modifier combination rather than a bare fn key)")
                if KarabinerRule.isKarabinerInstalled {
                    let installed = FileManager.default.fileExists(atPath: KarabinerRule.ruleFile.path)
                    print("  · Karabiner-Elements is installed — it can give you back the")
                    print("    fn key, since it already has Input Monitoring."
                          + (installed ? " Rule already written." : ""))
                    if !installed { print("    Run: Rawi --install-karabiner-rule") }
                }
            }
            if !status.accessibility {
                print("  · text is placed on the clipboard; press Cmd-V to paste it")
                print("    (auto-paste needs Accessibility and has no workaround)")
            }
        }
    }

    /// launchd is the parent of an app the user opened; a shell is the parent of
    /// one they ran by path.
    static var launchedFromTerminal: Bool { getppid() != 1 }

    static var appIsRunning: Bool {
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.welaghil.rawi" && $0.processIdentifier != mine
        }
    }

    /// `unknown` is for a check this process is not in a position to make: it
    /// prints a question rather than a verdict, and offers no fix for a problem
    /// that may not exist.
    private static func line(_ name: String, _ ok: Bool, unknown: Bool = false,
                             detail: String? = nil, fix: String) {
        let mark = unknown ? " ?  " : (ok ? "OK  " : "MISS")
        let padded = name.padding(toLength: 17, withPad: " ", startingAt: 0)
        print("  [\(mark)] \(padded) \(detail ?? "")")
        if !ok, !unknown { print("           ↳ \(fix)") }
    }

}
