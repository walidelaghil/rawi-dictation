import AVFoundation
import Foundation
import WhisperFlowCore

/// `WhisperFlow --doctor` prints everything needed to diagnose a setup problem
/// without guessing: permissions, resolved paths, and the active providers.
enum Doctor {
    static func run() async {
        let status = Permissions.current()
        print("WhisperFlow doctor\n")

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
        print("  hotkey            \(config.hotkey)")
        print("  engine            \(config.engine.rawValue)")
        print("  cleanup           \(config.cleanup.provider.rawValue)"
              + (config.cleanup.provider == .off ? "" : " (\(config.cleanup.model))"))
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
                 fix: "brew install ollama && ollama serve && ollama pull \(config.cleanup.model)")
        } else if config.cleanup.provider == .off {
            print("  — disabled; the raw transcript is inserted as-is")
        } else {
            let key = config.cleanup.provider == .openai ? "OPENAI_API_KEY" : "ANTHROPIC_API_KEY"
            line(key, env[key]?.isEmpty == false, detail: "from \(Config.envFile.path)",
                 fix: "add \(key)=... to ~/.config/whisperflow/.env")
        }

        print("")
        if status.allGranted {
            print("All permissions granted.")
        } else {
            print("Missing: \(status.missing.joined(separator: ", "))")
            print("The app runs without them, but:")
            if !status.inputMonitoring { print("  · the hotkey will not respond") }
            if !status.accessibility { print("  · text is copied but not pasted") }
            if !status.microphone { print("  · nothing can be recorded") }
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
