import Foundation

/// Append-only history on disk, held in memory for search.
///
/// Each line is sealed when a cipher is given, and entries older than the
/// retention window are removed along with any audio they kept. A file written by
/// an older build — plain JSON lines — is read, then rewritten sealed at once, so
/// upgrading never leaves the old readable file behind.
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
    private let cipher: (any HistoryCipher)?
    private var retentionDays: Int
    private let now: @Sendable () -> Date

    /// The prefix a sealed line carries. A line without it is an older plain one.
    static let sealedPrefix = "enc1:"

    public static var defaultURL: URL {
        Config.supportDirectory.appendingPathComponent("history.jsonl")
    }

    /// `retentionDays` of 0 keeps entries until the limit pushes them out.
    public init(url: URL = HistoryStore.defaultURL, limit: Int = 500,
                retentionDays: Int = 0, cipher: (any HistoryCipher)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.limit = max(1, limit)
        self.retentionDays = max(0, retentionDays)
        self.cipher = cipher
        self.now = now
        load()
    }

    /// Whether what is on disk is sealed.
    public var isEncrypted: Bool { cipher != nil }

    /// Changes the retention window, pruning straight away.
    public func setRetention(days: Int) {
        lock.withLock {
            retentionDays = max(0, days)
            if pruneLocked() { rewriteLocked() }
        }
    }

    public var count: Int { lock.withLock { entries.count } }
    /// The cap, so a screen can state it rather than repeat a literal.
    public var cap: Int { limit }

    public func all() -> [HistoryEntry] { lock.withLock { entries } }

    public func append(_ entry: HistoryEntry) {
        lock.withLock {
            entries.insert(entry, at: 0)
            if pruneLocked() || entries.count > limit {
                if entries.count > limit { removeOldestLocked(entries.count - limit) }
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
            for entry in entries { removeAudio(of: entry) }
            entries.removeAll()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Drops entries past the retention window. Caller holds the lock. Returns
    /// whether anything went.
    private func pruneLocked() -> Bool {
        guard retentionDays > 0 else { return false }
        let cutoff = now().addingTimeInterval(-Double(retentionDays) * 86_400)
        let expired = entries.filter { $0.at < cutoff }
        guard !expired.isEmpty else { return false }
        expired.forEach(removeAudio(of:))
        entries.removeAll { $0.at < cutoff }
        return true
    }

    private func removeOldestLocked(_ count: Int) {
        entries.suffix(count).forEach(removeAudio(of:))
        entries.removeLast(count)
    }

    /// Deletes recordings no history row points at.
    ///
    /// Audio is removed as each dictation finishes, but not every dictation
    /// finishes: a crash, a run that deliberately does not record, a test suite
    /// pointed at the wrong directory. What is left cannot be reached from
    /// anywhere in the app, so retention never sees it and "clear all" never
    /// touches it — it is a pile of your speech that nothing can delete. Found
    /// end to end with 596 files, 38 MB, most of them silence.
    ///
    /// `graceSeconds` keeps the recording being spoken into right now, which has
    /// no row yet because it has not finished.
    @discardableResult
    public func sweepOrphanedAudio(in directory: URL, graceSeconds: Double = 3_600,
                                   now: Date = Date()) -> Int {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let kept = Set(lock.withLock { entries.compactMap(\.audioPath) })
        var removed = 0
        for name in names where name.hasSuffix(".wav") {
            let path = directory.appendingPathComponent(name).path
            guard !kept.contains(path) else { continue }
            let modified = (try? manager.attributesOfItem(atPath: path)[.modificationDate]) as? Date
            guard let modified, now.timeIntervalSince(modified) > graceSeconds else { continue }
            if (try? manager.removeItem(atPath: path)) != nil { removed += 1 }
        }
        return removed
    }

    /// A failed dictation keeps its recording so it can be retried. When its row
    /// goes, the recording goes with it — otherwise the audio outlives the record
    /// that was the only way to find it.
    private func removeAudio(of entry: HistoryEntry) {
        guard let path = entry.audioPath else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Disk

    private func load() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [HistoryEntry] = []
        var sawPlain = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let data: Data
            if line.hasPrefix(Self.sealedPrefix) {
                // Sealed with a key this Mac no longer has costs that entry, never the
                // file — and never a crash.
                guard let cipher,
                      let sealed = Data(base64Encoded: String(line.dropFirst(Self.sealedPrefix.count))),
                      let opened = try? cipher.open(sealed) else { continue }
                data = opened
            } else {
                sawPlain = true
                data = Data(line.utf8)
            }
            // A truncated write from a crash costs that entry, never the file.
            guard let entry = try? decoder.decode(HistoryEntry.self, from: data) else { continue }
            loaded.append(entry)
        }
        entries = loaded.sorted { $0.at > $1.at }
        var changed = pruneLocked()
        if entries.count > limit { removeOldestLocked(entries.count - limit); changed = true }
        // An older plain file is sealed the moment a cipher is available.
        if changed || (sawPlain && cipher != nil) { rewriteLocked() }
    }

    private func encode(_ entry: HistoryEntry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // No pretty-printing: one entry must be exactly one line.
        guard let data = try? encoder.encode(entry) else { return nil }
        guard let cipher else { return String(decoding: data, as: UTF8.self) }
        // Base64 has no newlines, so a sealed entry is still exactly one line.
        guard let sealed = try? cipher.seal(data) else { return nil }
        return Self.sealedPrefix + sealed.base64EncodedString()
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
