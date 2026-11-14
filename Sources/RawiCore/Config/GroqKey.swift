import Foundation

/// The Groq key: checked, stored, and the settings that use it.
///
/// Groq is the default because it is the fast path. Measured on a 16 GB M4: local
/// whisper.cpp waited a median 8 s after half an hour idle (macOS had paged the
/// model out), Groq answers in about 0.3–0.8 s whatever the Mac is doing. Local
/// stays as the fallback when Groq is unreachable, and as the choice for anyone
/// who wants nothing to leave the Mac.
///
/// The key used to be set by hand in a hidden file. Done that way the line from
/// the instructions, placeholder and all, ended up in the file above the real key.
/// Setup now takes it in a field, checks it with Groq, and writes it here.
public enum GroqKey {
    /// Posted after a key is saved, so the running app picks it up without waiting
    /// for config.json to change.
    public static let changed = Notification.Name("RawiGroqKeyChanged")
    public static let consoleURL = URL(string: "https://console.groq.com/keys")!
    static let modelsURL = URL(string: "https://api.groq.com/openai/v1/models")!

    public static func isSet(in env: DotEnv) -> Bool {
        !(env["GROQ_API_KEY"] ?? "").isEmpty
    }

    public enum Problem: Error, LocalizedError, Equatable {
        case empty
        case rejected
        case unreachable(String)
        public var errorDescription: String? {
            switch self {
            case .empty: "Paste the key first."
            case .rejected: "Groq did not accept that key. Copy it again from console.groq.com/keys."
            case .unreachable(let why): "Could not reach Groq to check the key (\(why))."
            }
        }
    }

    /// Asks Groq whether the key works, before anything is written.
    public static func validate(_ key: String, session: URLSession = .shared) async throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Problem.empty }
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 10
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw Problem.unreachable(error.localizedDescription)
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return
        case 401, 403: throw Problem.rejected
        case let status: throw Problem.unreachable("HTTP \(status)")
        }
    }

    /// Writes the key into `.env`, replacing every earlier `GROQ_API_KEY` line and
    /// keeping the rest of the file as it was. Readable by you alone.
    public static func save(_ key: String, to url: URL = Config.envFile) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Problem.empty }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("export ") { trimmed = String(trimmed.dropFirst(7)) }
                return !trimmed.hasPrefix("GROQ_API_KEY=") && !trimmed.hasPrefix("GROQ_API_KEY =")
            }
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines.append("GROQ_API_KEY=\(key)")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Transcription, cleanup and transforms all through Groq, with the models
    /// chosen by measurement (see `CleanupProviderFactory.defaultModels`).
    public static func useGroq(_ config: inout Config) {
        config.engine = .groq
        config.cleanup.provider = .groq
        config.cleanup.models = CleanupProviderFactory.defaultModels(for: .groq)
        // Pins belong to the provider they were made on: "gemma3:4b" is an
        // Ollama name Groq does not serve.
        config.cleanup.transformModel = ""
        config.cleanup.polishModel = ""
    }
}
