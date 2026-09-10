import Foundation

/// Minimal `.env` reader. Values are never shell-expanded and never logged.
public struct DotEnv: Sendable {
    private var values: [String: String] = [:]

    public init(contents: String) {
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            value = Self.unquote(value)
            values[key] = value
        }
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" else {
            return s
        }
        return String(s.dropFirst().dropLast())
    }

    public subscript(_ key: String) -> String? { values[key] }

    public var keys: Set<String> { Set(values.keys) }

    public static func load(from url: URL) -> DotEnv {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return DotEnv(contents: "")
        }
        return DotEnv(contents: text)
    }
}
