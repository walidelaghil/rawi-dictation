import AVFoundation
import Foundation
import RawiCore

/// `Rawi --doctor` prints everything needed to diagnose a setup problem
/// without guessing: permissions, resolved paths, and the active providers.
enum Doctor {
    static func run() async {
        let status = Permissions.current()
        print("Rawi doctor\n")

        print("Permissions")
        line("Microphone", status.microphone,
             fix: "System Settings → Privacy & Security → Microphone")
        line("Input Monitoring", status.inputMonitoring,
             fix: "System Settings → Privacy & Security → Input Monitoring (add with +)")
        line("Accessibility", status.accessibility,
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
        print("  hotkey            \(config.hotkey)")
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
        line("model", modelExists, detail: modelPath,
             fix: "see README → Install → download a model")

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
        if status.allGranted {
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

    private static func line(_ name: String, _ ok: Bool,
                             detail: String? = nil, fix: String) {
        let mark = ok ? "OK  " : "MISS"
        let padded = name.padding(toLength: 17, withPad: " ", startingAt: 0)
        print("  [\(mark)] \(padded) \(detail ?? "")")
        if !ok { print("           ↳ \(fix)") }
    }

}
