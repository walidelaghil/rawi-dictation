import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RawiCore

/// Renders the screens that had no proof of their own: History, Transforms,
/// Dictionary and Snippets. Seeded with plausible content rather than lorem, so
/// the render shows what the screen looks like in use rather than empty.
///
/// Each writes a PNG when given an output path, the way the other proofs do:
///   RAWI_PROOF_SCREENS=/tmp/shots swift test --filter ScreenProofTests
@Suite("Screen proofs") @MainActor struct ScreenProofTests {
    static var out: URL? {
        ProcessInfo.processInfo.environment["RAWI_PROOF_SCREENS"].map {
            URL(fileURLWithPath: $0)
        }
    }

    func tmp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rawi-proof-\(name)-\(UUID().uuidString)")
    }

    func shoot(_ view: some View, _ name: String, width: CGFloat, height: CGFloat) throws {
        guard let directory = Self.out else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("\(name).png"))
    }

    func seededHistory() -> HistoryStore {
        let store = HistoryStore(url: tmp("hist").appendingPathExtension("jsonl"))
        let rows: [(String, String, String, Script)] = [
            ("Ship the beta on Thursday, then write the release notes.",
             "so ship the beta on thursday and then um write the release notes",
             "Slack", .latin),
            ("بالمناسبة راجعت صفحة الأسعار وأعتقد أن الباقة الوسطى تربك العملاء.",
             "بالمناسبة راجعت صفحة الاسعار واعتقد ان الباقة الوسطى تربك العملاء",
             "Notion", .arabic),
            ("The migration finished last night and every service came back clean.",
             "the migration finished last night and every service came back clean",
             "Jira", .latin),
            ("Let's meet on Wednesday at 3 o'clock.",
             "let's meet on tuesday sorry I mean wednesday at 3 o'clock",
             "Mail", .latin),
        ]
        for (index, row) in rows.enumerated() {
            store.append(HistoryEntry(
                at: Date().addingTimeInterval(Double(-index) * 900),
                cleaned: row.0, raw: row.1, script: row.3,
                appName: row.2, bundleID: "com.example.\(row.2.lowercased())",
                durationSeconds: 4 + Double(index), peakLevel: 0.05,
                guardRejected: false))
        }
        return store
    }

    @Test("History") func history() throws {
        let model = HistoryViewModel(store: seededHistory())
        model.appearance = .dark
        try shoot(HistoryView(model: model), "history", width: 860, height: 430)
    }

    @Test("Transforms") func transforms() throws {
        let model = TransformsViewModel(store: TransformStore(url: tmp("tf").appendingPathExtension("json")))
        model.appearance = .dark
        model.trySpoken = "make it shorter"
        model.tryText = "So I think the main thing we need to get across is that the "
                      + "migration finished on time and nothing broke."
        try shoot(TransformsView(model: model), "transforms", width: 860, height: 640)
    }

    func seededVocabulary() -> VocabularyViewModel {
        let store = VocabularyStore(url: tmp("vocab").appendingPathExtension("json"))
        store.addTerm("Salla", note: "you corrected “Sala” in Jira")
        store.addTerm("Kandji", note: "you corrected “Kanjee” in Slack")
        store.addTerm("Argo CD")
        store.addSnippet(trigger: "my email", expansion: "rawi@example.com")
        store.addSnippet(trigger: "standup link", expansion: "https://meet.example.com/standup")
        store.addSnippet(trigger: "sig", expansion: "Best, Sam")
        let model = VocabularyViewModel(store: store,
                                        history: HistoryStore(url: tmp("vh").appendingPathExtension("jsonl")))
        model.appearance = .dark
        return model
    }

    @Test("Dictionary") func dictionary() throws {
        try shoot(DictionaryScreen(model: seededVocabulary()), "dictionary", width: 860, height: 290)
    }

    @Test("Snippets") func snippets() throws {
        try shoot(SnippetsScreen(model: seededVocabulary()), "snippets", width: 860, height: 300)
    }
}
