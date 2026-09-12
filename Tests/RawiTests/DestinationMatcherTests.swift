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
