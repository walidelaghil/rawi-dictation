import Testing
import Foundation
@testable import RawiCore

@Suite("DestinationMatcher") struct DestinationMatcherTests {
    let rules = DestinationStore.defaults
    let brave = "com.brave.Browser"

    @Test("a bundle-only rule matches its app") func bundleOnly() {
        let hit = DestinationMatcher.match(bundleID: "com.apple.Terminal", url: nil, rules: rules)
        #expect(hit?.name == "Commit message")
    }

    @Test("a URL pattern beats a bundle-only rule") func urlWins() {
        let extra = DestinationRule(name: "Any browser", bundleIDs: [brave],
                                    instruction: "generic")
        let hit = DestinationMatcher.match(
            bundleID: brave, url: "https://app.slack.com/client/T01/C02", rules: rules + [extra])
        #expect(hit?.name == "Slack")
    }

    @Test("a longer URL pattern wins — a DM is not just Slack") func dmBeatsChannel() {
        // This ordering is the only reason DMs can be treated differently.
        let hit = DestinationMatcher.match(
            bundleID: brave, url: "https://app.slack.com/client/T01/D9ABC", rules: rules)
        #expect(hit?.name == "Slack · direct message")
    }

    @Test("a Jira ticket in Brave matches") func jira() {
        let hit = DestinationMatcher.match(
            bundleID: brave, url: "https://salla.atlassian.net/browse/ENG-412", rules: rules)
        #expect(hit?.name == "Jira ticket")
    }

    @Test("the native Slack app matches without any URL") func nativeSlack() {
        let hit = DestinationMatcher.match(
            bundleID: "com.tinyspeck.slackmacgap", url: nil, rules: rules)
        #expect(hit?.name == "Slack")
    }

    @Test("a disabled rule never matches") func disabled() {
        var off = rules
        for i in off.indices { off[i].enabled = false }
        #expect(DestinationMatcher.match(bundleID: "com.apple.Terminal", url: nil,
                                         rules: off) == nil)
    }

    @Test("no match returns nil rather than a default") func noMatch() {
        #expect(DestinationMatcher.match(bundleID: "com.unknown.App", url: nil,
                                         rules: rules) == nil)
    }

    @Test("a browser with an unreadable URL matches no URL rule") func nilURL() {
        // Automation denied, or no window: no rule rather than a guess.
        let hit = DestinationMatcher.match(bundleID: brave, url: nil, rules: rules)
        #expect(hit == nil)
    }

    @Test("a URL pattern constrains browsers only") func patternScopedToBrowsers() {
        // One rule covers "the Slack app, or slack.com in a browser". In the native
        // app there is no URL, and requiring one would mean it never fired there.
        #expect(DestinationMatcher.match(bundleID: "com.tinyspeck.slackmacgap",
                                         url: nil, rules: rules)?.name == "Slack")
        #expect(DestinationMatcher.match(bundleID: brave,
                                         url: "https://unrelated.com", rules: rules) == nil)
    }

    @Test("globs match at the start, middle and end") func globs() {
        #expect(DestinationMatcher.globMatches("*slack.com*", "https://app.slack.com/client"))
        #expect(DestinationMatcher.globMatches("https://*", "https://example.com"))
        #expect(DestinationMatcher.globMatches("*/browse/*", "https://x.atlassian.net/browse/A-1"))
        #expect(DestinationMatcher.globMatches("*.pdf", "https://x.com/a.pdf"))
        #expect(!DestinationMatcher.globMatches("*.pdf", "https://x.com/a.pdf?v=1"))
    }

    @Test("a glob for a host does not match a lookalike") func lookalike() {
        // "*app.slack.com/client/*" must not be satisfied by a lookalike domain.
        #expect(!DestinationMatcher.globMatches("*app.slack.com/client/*",
                                                "https://evil.com/?x=app.slack.com"))
    }

    @Test("an exact pattern with no star matches only itself") func exact() {
        #expect(DestinationMatcher.globMatches("https://a.com", "https://a.com"))
        #expect(!DestinationMatcher.globMatches("https://a.com", "https://a.com/b"))
    }
}

@Suite("DestinationStore") struct DestinationStoreTests {
    func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-dest-\(UUID().uuidString).json")
    }

    @Test("a fresh store ships the built-in rules, enabled") func defaults() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = DestinationStore(url: url)
        #expect(s.rules.count == DestinationStore.defaults.count)
        #expect(s.rules.allSatisfy { $0.enabled })
        #expect(s.rules.allSatisfy { $0.isBuiltIn })
    }

    @Test("Brave is covered by every browser rule") func brave() {
        // Brave is the browser actually in use here, so this is not incidental.
        for rule in DestinationStore.defaults where rule.urlPattern != nil {
            #expect(rule.bundleIDs.contains("com.brave.Browser"), "\(rule.name) omits Brave")
        }
    }

    @Test("a user rule can be added and removed") func userRule() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = DestinationStore(url: url)
        let rule = DestinationRule(name: "Mine", bundleIDs: ["com.x"], instruction: "y")
        s.add(rule)
        #expect(DestinationStore(url: url).rules.contains { $0.name == "Mine" })
        s.remove(rule.id)
        #expect(!DestinationStore(url: url).rules.contains { $0.name == "Mine" })
    }

    @Test("a built-in can be disabled but not deleted") func builtInProtected() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = DestinationStore(url: url)
        let builtIn = s.rules.first { $0.isBuiltIn }!
        s.remove(builtIn.id)
        #expect(s.rules.contains { $0.id == builtIn.id }, "deleting leaves no way back")
        s.setEnabled(builtIn.id, false)
        #expect(DestinationStore(url: url).rules.first { $0.id == builtIn.id }?.enabled == false)
    }

    @Test("instructions are about shape, never about content") func shapeOnly() {
        // A rule that invents facts would be rejected by CleanupGuard anyway, and
        // should not exist in the first place.
        for rule in DestinationStore.defaults {
            let text = rule.instruction.lowercased()
            #expect(!text.contains("add "), "\(rule.name) tells the model to add something")
            #expect(!text.contains("summarise") && !text.contains("summarize"),
                    "\(rule.name) tells the model to summarise")
        }
    }
}

@MainActor
@Suite("Destinations applied") struct DestinationApplicationTests {
    func rig(_ rule: DestinationRule?) -> (DictationController, FakeCleanup, Recorded) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        e.result = .success("we should ship this on friday")
        c.result = .success("We should ship this on Friday.")
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: FakeInserter(), log: FakeLog())
        ctl.frontmostApp = { ("Slack", "com.tinyspeck.slackmacgap") }
        ctl.destination = { _ in rule }
        let box = Recorded()
        ctl.onRecord = { box.append($0) }
        return (ctl, c, box)
    }

    @Test("the matched rule's instruction reaches cleanup") func instructionApplied() async {
        let rule = DestinationRule(name: "Slack", instruction: "One short paragraph.")
        let (ctl, cleanup, _) = rig(rule)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(cleanup.lastInstruction == "One short paragraph.")
    }

    @Test("no match means no instruction, not an empty rule") func noRule() async {
        let (ctl, cleanup, _) = rig(nil)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(cleanup.lastInstruction.isEmpty)
    }

    @Test("history records which rule shaped it") func recorded() async {
        let (ctl, _, box) = rig(DestinationRule(name: "Slack", instruction: "x"))
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(box.entries.first?.destination == "Slack")
    }

    @Test("the destination is resolved at key-press") func capturedEarly() async {
        let (ctl, cleanup, _) = rig(DestinationRule(name: "Slack", instruction: "first"))
        await ctl.handle(.beganHold)
        ctl.destination = { _ in DestinationRule(name: "Other", instruction: "second") }
        await ctl.handle(.endedHold)
        #expect(cleanup.lastInstruction == "first")
    }

    @Test("a rule cannot exempt cleanup from the guard") func guardStillApplies() async {
        // A destination rule shapes output; it is not a licence to lose the
        // dictation. The guard runs after cleanup either way.
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let inserter = FakeInserter()
        let long = "we should move the deadline to Friday because the API work is not done"
        e.result = .success(long)
        c.result = .success("ok")            // cleanup destroyed it
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: inserter, log: FakeLog())
        ctl.destination = { _ in DestinationRule(name: "Terse", instruction: "Be very brief.") }
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.inserted.first == long, "the guard must still protect your words")
    }

    @Test("history written before this field still loads") func backCompat() throws {
        let json = #"""
        {"id":"11111111-1111-1111-1111-111111111111","at":"2026-09-12T10:00:00Z",
         "cleaned":"x","raw":"x","script":"latin","appName":"Slack","bundleID":"b",
         "durationSeconds":1,"peakLevel":0.3,"guardRejected":false}
        """#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let entry = try d.decode(HistoryEntry.self, from: Data(json.utf8))
        #expect(entry.destination == nil)
    }
}
