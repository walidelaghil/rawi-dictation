import Testing
import Foundation
@testable import RawiCore

@Suite("HistoryEntry") struct HistoryEntryTests {
    func entry(cleaned: String = "Cleaned.", raw: String = "raw") -> HistoryEntry {
        HistoryEntry(at: Date(), cleaned: cleaned, raw: raw, script: .latin,
                     appName: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                     durationSeconds: 3.2, peakLevel: 0.4, guardRejected: false)
    }

    @Test("round-trips through JSON") func codable() throws {
        let e = entry()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(HistoryEntry.self, from: try encoder.encode(e))
        #expect(back.id == e.id)
        #expect(back.cleaned == e.cleaned)
        #expect(back.raw == e.raw)
        #expect(back.script == e.script)
    }

    @Test("knows whether cleanup changed anything") func wasCleaned() {
        #expect(entry(cleaned: "A", raw: "a").wasCleaned)
        #expect(!entry(cleaned: "same", raw: "same").wasCleaned)
    }

    @Test("a multi-line transcript collapses for list display") func oneLine() {
        #expect(entry(cleaned: "one\ntwo").oneLine == "one two")
    }

    @Test("defaults exclude a password manager and private messages") func exclusions() {
        let h = Config.default.history
        #expect(h.excludes("com.1password.1password"))
        #expect(h.excludes("com.apple.MobileSMS"))
        #expect(!h.excludes("com.tinyspeck.slackmacgap"))
        #expect(!h.excludes(nil))
    }

    @Test("history is on by default and capped") func defaults() {
        #expect(Config.default.history.enabled)
        #expect(Config.default.history.limit == 500)
    }

    @Test("a config predating the key still loads") func backCompat() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"fn"}"#.utf8))
        #expect(c.history.enabled)
        #expect(!c.history.excludedBundleIDs.isEmpty)
    }
}

@Suite("HistoryStore") struct HistoryStoreTests {
    func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-hist-\(UUID().uuidString).jsonl")
    }
    func entry(_ text: String, at: Date = Date()) -> HistoryEntry {
        HistoryEntry(at: at, cleaned: text, raw: text.lowercased(), script: .latin,
                     appName: "Slack", bundleID: "x", durationSeconds: 1,
                     peakLevel: 0.3, guardRejected: false)
    }

    @Test("appends survive a reload") func persists() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let a = HistoryStore(url: url); a.append(entry("one")); a.append(entry("two"))
        #expect(HistoryStore(url: url).all().count == 2)
    }

    @Test("newest comes first") func order() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url)
        s.append(entry("older", at: Date(timeIntervalSince1970: 1000)))
        s.append(entry("newer", at: Date(timeIntervalSince1970: 2000)))
        #expect(s.all().first?.cleaned == "newer")
    }

    @Test("the cap is enforced and drops the oldest") func cap() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url, limit: 5)
        for i in 0..<9 { s.append(entry("e\(i)", at: Date(timeIntervalSince1970: Double(i)))) }
        let all = s.all()
        #expect(all.count == 5)
        #expect(all.first?.cleaned == "e8")
        #expect(!all.contains { $0.cleaned == "e0" })
        #expect(HistoryStore(url: url).all().count == 5)
    }

    @Test("a corrupt line costs one entry, not the file") func corrupt() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url); s.append(entry("good one"))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"trunc\n".utf8))
        try handle.close()
        let reloaded = HistoryStore(url: url)
        #expect(reloaded.all().count == 1)
        #expect(reloaded.all().first?.cleaned == "good one")
    }

    @Test("purge empties both memory and disk") func purge() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url); s.append(entry("one"))
        s.purge()
        #expect(s.all().isEmpty)
        #expect(HistoryStore(url: url).all().isEmpty)
    }

    @Test("a single entry can be removed and stays removed") func remove() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url)
        s.append(entry("keep", at: Date(timeIntervalSince1970: 1)))
        s.append(entry("drop", at: Date(timeIntervalSince1970: 2)))
        let id = s.all().first { $0.cleaned == "drop" }!.id
        s.remove(id)
        #expect(s.all().map(\.cleaned) == ["keep"])
        #expect(HistoryStore(url: url).all().map(\.cleaned) == ["keep"])
    }

    @Test("a missing file is an empty history, not a crash") func missing() {
        #expect(HistoryStore(url: tmp()).all().isEmpty)
    }

    @Test("newlines in a transcript cannot corrupt the line format") func embeddedNewlines() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url)
        s.append(entry("line one\nline two"))
        #expect(HistoryStore(url: url).all().first?.cleaned == "line one\nline two")
        #expect(HistoryStore(url: url).all().count == 1)
    }

    @Test("Arabic survives the round trip") func arabic() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = HistoryStore(url: url)
        s.append(HistoryEntry(at: Date(), cleaned: "يعني تمام", raw: "يعني تمام",
                              script: .arabic, appName: "Mail", bundleID: "m",
                              durationSeconds: 1, peakLevel: 0.3, guardRejected: false))
        let back = HistoryStore(url: url).all().first
        #expect(back?.cleaned == "يعني تمام")
        #expect(back?.script == .arabic)
    }
}
