import Foundation
import Testing
@testable import RawiCore

@Suite("Your usage") struct UsageInsightsTests {
    let now = ISO8601DateFormatter().date(from: "2026-09-15T12:00:00Z")!
    func entry(_ text: String, raw: String? = nil, daysAgo: Double = 0, bundle: String? = "com.anthropic.claudefordesktop",
               app: String = "Claude", destination: String? = nil, seconds: Double = 6,
               script: Script = .latin, kind: EntryKind = .dictation) -> HistoryEntry {
        HistoryEntry(at: now.addingTimeInterval(-daysAgo * 86_400), cleaned: text, raw: raw ?? text,
                     destination: destination, script: script, appName: app, bundleID: bundle,
                     durationSeconds: seconds, peakLevel: 0.2, guardRejected: false, kind: kind)
    }
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test("places are grouped by what they are for, browser tabs by their destination") func places() {
        let entries = [entry("one two"), entry("three four"),
                       entry("five", bundle: "com.tinyspeck.slackmacgap", app: "Slack"),
                       entry("six", bundle: "com.brave.Browser", app: "Brave", destination: "Gmail replies")]
        let usage = UsageInsights.compute(from: entries, now: now, calendar: utc)
        #expect(usage.places.first?.place == .aiPrompts)
        #expect(usage.places.first?.dictations == 2)
        #expect(usage.places.contains { $0.place == .email })
        #expect(usage.appsUsed == 3)
    }

    @Test("the month trend compares whole calendar months") func trend() {
        let entries = [entry("a b c d", daysAgo: 1), entry("a b", daysAgo: 20)]
        let usage = UsageInsights.compute(from: entries, now: now, calendar: utc)
        #expect(usage.wordsThisMonth == 4)
        #expect(usage.wordsLastMonth == 2)
        #expect(usage.trend == 1.0)
    }

    @Test("fixes count what cleanup changed, and dictionary spellings separately") func fixes() {
        let e = entry("Send it to Salla today.", raw: "um send it to Sala today")
        let usage = UsageInsights.compute(from: [e], terms: ["Salla"], now: now, calendar: utc)
        #expect(usage.wordsTidied == 2)       // "um" gone, "Sala" became Salla
        #expect(usage.dictionaryFixes == 1)
    }

    @Test("transforms and failures are not your spoken words") func spokenOnly() {
        let usage = UsageInsights.compute(from: [entry("clipboard text here", kind: .transform),
                                                 entry("", kind: .failed), entry("hello there")],
                                          now: now, calendar: utc)
        #expect(usage.words == 2)
        #expect(usage.dictations == 1)
    }

    @Test("a dictation in both scripts counts as mixed") func mixed() {
        let usage = UsageInsights.compute(from: [entry("Send the تقرير to Sara", script: .latin),
                                                 entry("نرسل التقرير", script: .arabic)],
                                          now: now, calendar: utc)
        #expect(usage.mixedDictations == 1)
        #expect(usage.arabicWords == 2)
    }
}

@Suite("Your voice") struct VoiceInsightsTests {
    let now = Date()
    func e(_ text: String, raw: String? = nil, app: String = "Claude", at date: Date? = nil) -> HistoryEntry {
        HistoryEntry(at: date ?? now, cleaned: text, raw: raw ?? text, script: .latin, appName: app,
                     bundleID: nil, durationSeconds: 3, peakLevel: 0.2, guardRejected: false)
    }

    @Test("a phrase said three times across dictations is a catchphrase") func catchphrase() {
        let voice = VoiceInsights.compute(from: [e("Can you confirm the numbers?"), e("Can you confirm the date?"),
                                                 e("Great, can you confirm that one more time")])
        #expect(voice.catchphrase == "Can you confirm")
    }

    @Test("one repeated sentence in one dictation is not a habit") func notHabit() {
        let voice = VoiceInsights.compute(from: [e("ship it ship it ship it ship it")])
        #expect(voice.catchphrase == nil)
    }

    @Test("most used word skips grammar") func mostUsed() {
        let voice = VoiceInsights.compute(from: [e("we need the deck and we need the numbers"), e("I need it now")])
        #expect(voice.mostUsedWord == "need")
    }

    @Test("the filler you use most is the one cleanup took out most") func filler() {
        let voice = VoiceInsights.compute(from: [e("Send it today.", raw: "um like send it today"),
                                                 e("Call Sara.", raw: "like call Sara")])
        #expect(voice.filler?.word == "like")
        #expect(voice.filler?.count == 2)
    }

    @Test("peak moment reads like a person would say it") func peak() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let wednesday10 = ISO8601DateFormatter().date(from: "2026-09-16T10:15:00Z")!
        let voice = VoiceInsights.compute(from: [e("one two three four", at: wednesday10),
                                                 e("five", app: "Slack", at: wednesday10.addingTimeInterval(-86_400))],
                                          calendar: c)
        #expect(voice.peakMoment == "Wednesday at 10 a.m.")
        #expect(voice.peakApp == "Claude")
    }
}

@Suite("The written voice profile") struct VoiceProfileTests {
    @Test("a good reply is read, fenced or not") func parse() {
        let reply = "```json\n{\"archetype\": \"Insightful Clarifier\", \"summary\": \"You use voice to untangle workflows. You ask precise questions.\", \"peak\": \"Wednesday mornings in Claude.\"}\n```"
        let profile = VoiceProfile.parse(reply, words: 2000)
        #expect(profile?.archetype == "Insightful Clarifier")
        #expect(profile?.wordsAtCreation == 2000)
        #expect(profile?.wordsUntilUpdate(currentWords: 2500) == 1000)
    }

    @Test("a reply that leaks a private detail or rambles is refused") func refuse() {
        #expect(VoiceProfile.parse(#"{"archetype":"A","summary":"Email me at a@b.com","peak":"x"}"#, words: 1) == nil)
        #expect(VoiceProfile.parse(#"{"archetype":"The Very Long Archetype Name Here","summary":"s","peak":"p"}"#, words: 1) == nil)
        #expect(VoiceProfile.parse("I think you are a clarifier.", words: 1) == nil)
    }

    @Test("the sample sent to the model has private details removed") func redacts() {
        let entry = HistoryEntry(at: Date(), cleaned: "Send it to rawi@example.com or call +1 403 555 0199 via https://x.co/a",
                                 raw: "", script: .latin, appName: "Mail", bundleID: nil,
                                 durationSeconds: 2, peakLevel: 0.1, guardRejected: false)
        let usage = UsageInsights.compute(from: [entry])
        let request = VoiceProfile.request(entries: [entry], voice: VoiceInsights.compute(from: [entry]), usage: usage)
        #expect(!request.contains("rawi@example.com"))
        #expect(!request.contains("555"))
        #expect(!request.contains("https://"))
    }

    @Test("the profile is stored sealed and read back") func store() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vp-\(UUID().uuidString)")
        let store = VoiceProfileStore(url: url, cipher: InMemoryHistoryCipher())
        let profile = VoiceProfile(archetype: "Decisive Delegator", summary: "You assign work.", peak: "Mornings.",
                                   createdAt: Date(timeIntervalSince1970: 1_000_000), wordsAtCreation: 10)
        store.save(profile)
        #expect(!(String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) ?? "").contains("Delegator"))
        #expect(store.load() == profile)
    }
}

@Suite("Your voice, from your real history", .enabled(if: ProcessInfo.processInfo.environment["RAWI_LIVE_VOICE"] != nil))
struct VoiceLiveTests {
    @Test("computes and writes a profile") func real() async throws {
        let cipher = try FileKeyHistoryCipher()
        let entries = HistoryStore(cipher: cipher).all()
        let terms = VocabularyStore().terms.map(\.term)
        let usage = UsageInsights.compute(from: entries, terms: terms)
        let voice = VoiceInsights.compute(from: entries)
        print("USAGE words \(usage.words), wpm \(usage.wordsPerMinute), tidied \(usage.wordsTidied), dictionary \(usage.dictionaryFixes), places \(usage.places.map { "\($0.place.label) \($0.dictations)" }), streak \(usage.currentStreak)/\(usage.longestStreak), mixed \(usage.mixedDictations), arabic \(usage.arabicWords)")
        print("VOICE catchphrase \(voice.catchphrase ?? "-"), most used \(voice.mostUsedWord ?? "-"), corrected \(voice.mostCorrectedWord ?? "-"), filler \(voice.filler.map { "\($0.word) ×\($0.count)" } ?? "-"), peak \(voice.peakMoment ?? "-") in \(voice.peakApp ?? "-"), longest \(voice.longestDictationWords)")
        let model = ProcessInfo.processInfo.environment["RAWI_LIVE_VOICE"]!
        let writer = ChatCleanup(kind: .ollama, apiKey: nil, model: model, prompt: VoiceProfile.systemPrompt, wrap: { $0 })
        let started = Date()
        let reply = try await writer.clean(VoiceProfile.request(entries: entries, voice: voice, usage: usage), instruction: "")
        let profile = VoiceProfile.parse(reply, words: usage.words)
        print("PROFILE (\(Int(Date().timeIntervalSince(started) * 1000))ms): \(profile.map { "\($0.archetype) | \($0.summary) | \($0.peak)" } ?? "REFUSED: \(reply.prefix(300))")")
        #expect(profile != nil)
    }
}

import AppKit
import SwiftUI

@MainActor
@Suite("Insights proof") struct InsightsProofTests {
    func sampleHistory() -> HistoryStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ins-\(UUID().uuidString).jsonl")
        let store = HistoryStore(url: url)
        let texts = ["Can you confirm the rollout plan for the billing service before Friday",
                     "Draft a reply to the team saying the design review moved to Thursday",
                     "Can you confirm whether the export covers every region",
                     "Summarise the customer interviews and pull out the three biggest pains",
                     "Send Salla the updated contract and copy finance",
                     "نرسل التقرير إلى الفريق قبل يوم الخميس",
                     "Write the release notes for version four point two",
                     "Can you confirm the numbers in the quarterly deck"]
        let apps: [(String, String)] = [("Claude", "com.anthropic.claudefordesktop"), ("Slack", "com.tinyspeck.slackmacgap"),
                                        ("Notion", "notion.id"), ("Mail", "com.apple.mail"), ("Cursor", "com.todesktop.230313mzl4w4u92")]
        var seed = 11
        func next(_ n: Int) -> Int { seed = (seed * 48271) % 2147483647; return seed % n }
        for day in 0..<95 where next(10) < 7 {
            for _ in 0..<(1 + next(5)) {
                let text = texts[next(texts.count)]
                let app = next(10) < 6 ? apps[0] : apps[1 + next(4)]
                let when = Date().addingTimeInterval(-Double(day) * 86_400 - Double(next(36_000)))
                store.append(HistoryEntry(at: when, cleaned: text, raw: next(3) == 0 ? "um " + text.lowercased() : text,
                                          script: text.first!.isASCII ? .latin : .arabic, appName: app.0, bundleID: app.1,
                                          durationSeconds: Double(text.split(separator: " ").count) / 2.2,
                                          peakLevel: 0.2, guardRejected: false))
            }
        }
        return store
    }

    @Test("insights proof", .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF_INSIGHTS"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF_INSIGHTS"]!)
        var images: [NSImage] = []
        for (tab, appearance) in [(InsightsTab.usage, ResolvedAppearance.dark), (.voice, .light)] {
            let model = InsightsViewModel(store: sampleHistory())
            model.terms = { ["Salla"] }
            model.taught = { ["Salla", "Kandji"] }
            model.appearance = appearance
            model.tab = tab
            model.reload()
            model.profile = VoiceProfile(archetype: "Insightful Clarifier",
                                         summary: "You use your voice to untangle work before it starts, asking precise questions and confirming details so everyone lands on the same page.",
                                         peak: "", createdAt: Date().addingTimeInterval(-86_400 * 3),
                                         wordsAtCreation: max(0, model.usage.words - 400))
            let host = NSHostingView(rootView: InsightsView(model: model))
            host.frame = NSRect(x: 0, y: 0, width: 800, height: 1040)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(rep)
            images.append(image)
        }
        let gap: CGFloat = 14
        let width = images.reduce(0) { $0 + $1.size.width + gap } + gap
        let height = (images.map(\.size.height).max() ?? 0) + gap * 2
        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor(white: 0.45, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            var x = gap
            for image in images { image.draw(at: NSPoint(x: x, y: gap), from: .zero, operation: .sourceOver, fraction: 1); x += image.size.width + gap }
            return true
        }
        try NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: out)
    }
}
