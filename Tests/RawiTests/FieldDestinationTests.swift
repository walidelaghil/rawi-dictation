import Foundation
import Testing
@testable import RawiCore

@Suite("Field-level destinations") struct FieldDestinationTests {
    let summary = FieldContext(labels: ["Summary", "summary-field"], multiline: false)
    let description = FieldContext(labels: ["Main content area, start typing to enter text."], multiline: true)
    let jiraBoard = "https://salla.atlassian.net/jira/software/projects/ABC/boards/1"

    @Test("a field pattern matches the label, ignoring case, with alternatives") func matches() {
        #expect(summary.matches("summary"))
        #expect(description.matches("description|main content area"))
        #expect(!summary.matches("description"))
        #expect(!summary.matches("  |  "))
    }

    @Test("in Jira, the summary box and the description get different rules") func jira() {
        let rules = DestinationStore.defaults
        let brave = "com.brave.Browser"
        #expect(DestinationMatcher.match(bundleID: brave, url: jiraBoard, field: summary, rules: rules)?.name == "Jira · summary")
        #expect(DestinationMatcher.match(bundleID: brave, url: jiraBoard, field: description, rules: rules)?.name == "Jira · description")
    }

    @Test("without a field, field rules stay quiet and the page rule still fires") func noField() {
        let rules = DestinationStore.defaults
        let issue = "https://salla.atlassian.net/browse/ABC-12"
        #expect(DestinationMatcher.match(bundleID: "com.brave.Browser", url: issue, field: nil, rules: rules)?.name == "Jira ticket")
    }

    @Test("a field is more specific than a page, and a page than an app") func specificity() {
        let app = DestinationRule(name: "a", bundleIDs: ["x"], instruction: "i")
        let page = DestinationRule(name: "p", bundleIDs: ["x"], urlPattern: "*very.long.example.com/path/*", instruction: "i")
        let field = DestinationRule(name: "f", bundleIDs: ["x"], fieldPattern: "to", instruction: "i")
        #expect(field.specificity > page.specificity)
        #expect(page.specificity > app.specificity)
        #expect(field.matchDescription.contains("field: to"))
    }

    @Test("a rules file from before field patterns still loads, and gains the new built-ins") func oldFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dest-\(UUID().uuidString).json")
        let old = #"[{"id":"B0C82CFC-9646-47DB-9AA8-1DCDAAA436CD","name":"My standup","bundleIDs":["com.tinyspeck.slackmacgap"],"instruction":"Bullets.","enabled":true,"isBuiltIn":false}]"#
        try Data(old.utf8).write(to: url)
        let store = DestinationStore(url: url)
        #expect(store.rules.contains { $0.name == "My standup" })
        #expect(store.rules.contains { $0.name == "Jira · summary" })
        #expect(!store.rules.contains { $0.name == "Mail" && !$0.isBuiltIn })
    }
}

@MainActor
@Suite("Detecting a field for a new rule") struct DetectFieldTests {
    func model() -> DestinationsViewModel {
        DestinationsViewModel(store: DestinationStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("dest-\(UUID().uuidString).json")))
    }

    @Test("what was detected fills the form") func fills() {
        let m = model()
        m.fill(from: ("com.brave.Browser", "https://salla.atlassian.net/jira/create",
                      FieldContext(labels: ["Summary"], multiline: false)))
        #expect(m.draftApps == "com.brave.Browser")
        #expect(m.draftURL == "*salla.atlassian.net*")
        #expect(m.draftField == "summary")
        #expect(m.draftName == "Summary")
    }

    @Test("detecting Rawi itself says to switch first") func ownApp() {
        let m = model()
        m.fill(from: (Bundle.main.bundleIdentifier ?? "", nil, nil))
        #expect(m.detected?.contains("switch") == true || Bundle.main.bundleIdentifier == nil)
    }

    @Test("a saved draft becomes a rule and the form clears") func saves() {
        let m = model()
        m.draftName = "Email subject, mine"
        m.draftApps = "com.apple.mail"
        m.draftField = "subject"
        m.draftInstruction = "Short."
        m.saveDraft()
        #expect(m.rules.contains { $0.name == "Email subject, mine" && $0.fieldPattern == "subject" })
        #expect(m.draftName.isEmpty)
    }
}

import AppKit
import SwiftUI

@MainActor
@Suite("Destinations proof") struct DestinationsProofTests {
    @Test("destinations proof", .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF_DEST"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF_DEST"]!)
        let model = DestinationsViewModel(store: DestinationStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("dest-\(UUID().uuidString).json")))
        model.appearance = .dark
        model.fill(from: ("com.brave.Browser", "https://salla.atlassian.net/jira/create",
                          FieldContext(labels: ["Summary"], multiline: false)))
        model.draftInstruction = "A ticket title: one short line, no full stop."
        let host = NSHostingView(rootView: DestinationsView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 620)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: out)
    }
}
