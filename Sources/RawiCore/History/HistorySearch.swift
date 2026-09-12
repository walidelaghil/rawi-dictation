import Foundation

public struct HistoryFilter: Sendable, Equatable {
    public var query: String
    public var script: Script?
    public var bundleID: String?

    public init(query: String = "", script: Script? = nil, bundleID: String? = nil) {
        self.query = query
        self.script = script
        self.bundleID = bundleID
    }

    public var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && script == nil && bundleID == nil
    }
}

public enum HistorySearch {
    /// Search covers the cleaned text **and** the raw transcript.
    ///
    /// You remember what you said, not what came out. If cleanup removed
    /// "basically", searching for it must still find the dictation — otherwise the
    /// one word you remember is the one word that cannot find it.
    public static func apply(_ filter: HistoryFilter,
                             to entries: [HistoryEntry]) -> [HistoryEntry] {
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if let script = filter.script, entry.script != script { return false }
            if let bundleID = filter.bundleID, entry.bundleID != bundleID { return false }
            guard !query.isEmpty else { return true }
            return entry.cleaned.localizedCaseInsensitiveContains(query)
                || entry.raw.localizedCaseInsensitiveContains(query)
        }
    }

    /// The query hit the raw transcript but not the cleaned text — so the UI knows
    /// to surface the raw line, or the match looks like a bug.
    public static func matchedRawOnly(_ query: String, _ entry: HistoryEntry) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        return entry.raw.localizedCaseInsensitiveContains(q)
            && !entry.cleaned.localizedCaseInsensitiveContains(q)
    }

    /// Apps present in the history, for the filter control.
    public static func apps(in entries: [HistoryEntry]) -> [(id: String, name: String)] {
        var seen: [String: String] = [:]
        for e in entries {
            guard let id = e.bundleID else { continue }
            if seen[id] == nil { seen[id] = e.appName ?? id }
        }
        return seen.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }
}
