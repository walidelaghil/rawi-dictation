import Foundation

/// Append-only history on disk, held in memory for search.
///
/// JSONL rather than a database: an append is one line, the file stays readable
/// with `tail`, and a corrupt line costs one entry instead of the file. At 500
/// rows, loading and scanning in memory is free — an index would be machinery
/// with nothing to do.
public final class HistoryStore: @unchecked Sendable {
    private let url: URL
    private let limit: Int
    private let lock = NSLock()
    private var entries: [HistoryEntry] = []      // newest first

    public static var defaultURL: URL {
        Config.supportDirectory.appendingPathComponent("history.jsonl")
    }

    public init(url: URL = HistoryStore.defaultURL, limit: Int = 500) {
        self.url = url
        self.limit = max(1, limit)
        load()
    }

    public var count: Int { lock.withLock { entries.count } }

    public func all() -> [HistoryEntry] { lock.withLock { entries } }

    public func append(_ entry: HistoryEntry) {
        lock.withLock {
            entries.insert(entry, at: 0)
            if entries.count > limit {
                entries.removeLast(entries.count - limit)
                rewriteLocked()          // over the cap, so compact rather than append
            } else if let line = encode(entry) {
                appendLine(line)
            }
        }
    }

    public func remove(_ id: UUID) {
        lock.withLock {
            entries.removeAll { $0.id == id }
            rewriteLocked()
        }
    }

    public func purge() {
        lock.withLock {
            entries.removeAll()
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Disk

    private func load() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [HistoryEntry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // A truncated write from a crash costs that entry, never the file.
            guard let entry = try? decoder.decode(HistoryEntry.self, from: Data(line.utf8))
            else { continue }
            loaded.append(entry)
        }
        entries = loaded.sorted { $0.at > $1.at }
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    private func encode(_ entry: HistoryEntry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // No pretty-printing: one entry must be exactly one line.
        guard let data = try? encoder.encode(entry) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func appendLine(_ line: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Caller already holds the lock.
    private func rewriteLocked() {
        let body = entries.reversed().compactMap(encode).joined(separator: "\n")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data((body.isEmpty ? "" : body + "\n").utf8).write(to: url, options: .atomic)
    }
}
