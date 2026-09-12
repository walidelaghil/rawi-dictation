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
}
