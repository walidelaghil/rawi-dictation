import Foundation

/// What Ollama has actually pulled.
///
/// The settings screen offers these rather than a free-text box, because the most
/// common way to break cleanup is to name a model that is not installed — which
/// fails silently at the next dictation, not here.
public enum OllamaModels {
    public static func installed(timeout: TimeInterval = 1.5) async -> [String] {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// A rough ordering so the list does not need reading end to end: the models
    /// this app was tuned against first, then everything else alphabetically.
    public static func preferred(from installed: [String]) -> [String] {
        let known = ["qwen2.5:1.5b", "qwen2.5:3b"]
        return known.filter(installed.contains) + installed.filter { !known.contains($0) }
    }

    // MARK: - First run

    static let base = URL(string: "http://127.0.0.1:11434")!

    /// The models Rawi's defaults use, and what each is for, in the order a first run
    /// should fetch them: the one every English dictation needs first.
    public static func required(for config: Config) -> [(name: String, purpose: String)] {
        var list: [(String, String)] = []
        func add(_ name: String, _ purpose: String) {
            guard !name.isEmpty, !list.contains(where: { $0.0 == name }) else { return }
            list.append((name, purpose))
        }
        add(config.cleanup.models.latin, "polish for English")
        add(config.cleanup.models.arabic, "polish for Arabic and mixed speech")
        add(config.cleanup.transformModel, "transforms")
        return list
    }

    public static func isReachable() async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// The same list as a set, with `:latest` names also under their bare name, for
    /// checking whether a configured model is present.
    public static func installedNames() async -> Set<String> {
        var names = Set<String>()
        for name in await installed() {
            names.insert(name)
            if name.hasSuffix(":latest") { names.insert(String(name.dropLast(7))) }
        }
        return names
    }

    /// One line of Ollama's streamed pull progress, as a fraction when it has one.
    static func progress(fromLine line: String) -> (status: String, fraction: Double?)? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = root["error"] as? String { return ("error: \(error)", nil) }
        let status = root["status"] as? String ?? ""
        if let completed = root["completed"] as? Double, let total = root["total"] as? Double, total > 0 {
            return (status, min(1, completed / total))
        }
        return (status, status == "success" ? 1 : nil)
    }

    /// Pulls a model, reporting progress. Throws with Ollama's own message on failure.
    public static func pull(_ name: String,
                            progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3600
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "stream": true])
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        // Several layers download in turn; the largest decides how long it takes, so
        // progress follows whichever layer is moving rather than resetting to zero.
        for try await line in bytes.lines {
            guard let update = Self.progress(fromLine: line) else { continue }
            if update.status.hasPrefix("error:") {
                throw ModelStoreError.downloadFailed(String(update.status.dropFirst(7)))
            }
            if let fraction = update.fraction { progress(fraction) }
        }
    }
}
