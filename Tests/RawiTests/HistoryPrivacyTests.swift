import CryptoKit
import Foundation
import Testing
@testable import RawiCore

@Suite("History on disk") struct HistoryPrivacyTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rawi-history-\(UUID().uuidString)").appendingPathComponent("h.jsonl")
    }
    func entry(_ text: String, daysAgo: Double = 0, now: Date = Date(), audio: String? = nil) -> HistoryEntry {
        HistoryEntry(at: now.addingTimeInterval(-daysAgo * 86_400), cleaned: text, raw: text,
                     script: .latin, appName: "Notes", bundleID: "com.apple.Notes",
                     durationSeconds: 2, peakLevel: 0.2, guardRejected: false, audioPath: audio)
    }

    @Test("what you said is not readable in the file") func sealed() throws {
        let url = tempURL()
        let store = HistoryStore(url: url, cipher: InMemoryHistoryCipher())
        store.append(entry("the launch moves to Tuesday"))
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(!onDisk.contains("Tuesday"))
        #expect(onDisk.hasPrefix(HistoryStore.sealedPrefix))
    }

    @Test("sealed history reads back with the same key") func roundTrip() {
        let url = tempURL(), key = SymmetricKey(size: .bits256)
        HistoryStore(url: url, cipher: InMemoryHistoryCipher(key: key)).append(entry("hello Salla"))
        let back = HistoryStore(url: url, cipher: InMemoryHistoryCipher(key: key))
        #expect(back.all().map(\.cleaned) == ["hello Salla"])
    }

    @Test("with the wrong key, entries are skipped rather than crashing") func wrongKey() {
        let url = tempURL()
        HistoryStore(url: url, cipher: InMemoryHistoryCipher()).append(entry("secret"))
        #expect(HistoryStore(url: url, cipher: InMemoryHistoryCipher()).all().isEmpty)
    }

    @Test("an older plain file is read, then sealed straight away") func migrates() throws {
        let url = tempURL()
        HistoryStore(url: url).append(entry("plain from an older build"))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("older build"))
        let upgraded = HistoryStore(url: url, cipher: InMemoryHistoryCipher())
        #expect(upgraded.all().map(\.cleaned) == ["plain from an older build"])
        #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("older build"))
    }

    @Test("entries past the retention window go, with their audio") func retention() throws {
        let url = tempURL(), now = Date()
        let audio = url.deletingLastPathComponent().appendingPathComponent("kept.wav")
        try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: audio)
        let plain = HistoryStore(url: url)
        plain.append(entry("old failure", daysAgo: 40, now: now, audio: audio.path))
        plain.append(entry("recent", daysAgo: 2, now: now))

        let kept = HistoryStore(url: url, retentionDays: 30, now: { now })
        #expect(kept.all().map(\.cleaned) == ["recent"])
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        // And it stays gone after a reload.
        #expect(HistoryStore(url: url).all().map(\.cleaned) == ["recent"])
    }

    @Test("changing the window prunes straight away; 0 keeps everything") func changeWindow() {
        let url = tempURL(), now = Date()
        let store = HistoryStore(url: url, retentionDays: 0, now: { now })
        store.append(entry("a", daysAgo: 100, now: now))
        store.append(entry("b", daysAgo: 1, now: now))
        #expect(store.all().count == 2)
        store.setRetention(days: 7)
        #expect(store.all().map(\.cleaned) == ["b"])
    }

    @Test("settings from an older config get retention and encryption defaults") func settingsDefaults() throws {
        let json = #"{"enabled":true,"limit":500,"excludedBundleIDs":[]}"#
        let settings = try JSONDecoder().decode(HistorySettings.self, from: Data(json.utf8))
        #expect(settings.retentionDays == 90)
        #expect(settings.encrypted)
    }
}

@Suite("The history key file") struct HistoryKeyFileTests {
    func keyURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rawi-key-\(UUID().uuidString)")
            .appendingPathComponent("Keys").appendingPathComponent("history.key")
    }

    @Test("the key is created private, and the same key comes back") func privateAndStable() throws {
        let url = keyURL()
        let first = try FileKeyHistoryCipher(url: url)
        let sealed = try first.seal(Data("hello".utf8))
        let again = try FileKeyHistoryCipher(url: url)
        #expect(String(decoding: try again.open(sealed), as: UTF8.self) == "hello")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("an existing key is carried over, so older sealed history still opens") func migrates() throws {
        let legacy = SymmetricKey(size: .bits256)
        let sealed = try InMemoryHistoryCipher(key: legacy).seal(Data("from the keychain era".utf8))
        let url = keyURL()
        var asked = 0
        let cipher = try FileKeyHistoryCipher(url: url, migrate: { asked += 1; return legacy })
        #expect(String(decoding: try cipher.open(sealed), as: UTF8.self) == "from the keychain era")
        // Only the first time: with a key file present, nothing else is asked.
        _ = try FileKeyHistoryCipher(url: url, migrate: { asked += 1; return nil })
        #expect(asked == 1)
    }
}
