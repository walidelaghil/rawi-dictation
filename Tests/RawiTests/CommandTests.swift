import Foundation
import Testing
@testable import RawiCore

@Suite("Matching what you said to a command") struct CommandMatcherTests {
    let commands = [
        SpokenCommand(phrase: "ask Claude", action: .openLink("https://claude.ai/new?q={text}")),
        SpokenCommand(phrase: "remind me to", action: .reminder(list: "")),
        SpokenCommand(phrase: "new ticket", action: .openLink("https://x.atlassian.net/create?summary={text}")),
        SpokenCommand(phrase: "new ticket for design", action: .openLink("https://x.atlassian.net/design?summary={text}")),
    ]

    @Test("the phrase has to start what you said, and the rest is the text") func prefix() {
        let match = CommandMatcher.match("Ask Claude, why is the build failing?", in: commands)
        #expect(match?.command.phrase == "ask Claude")
        #expect(match?.text == "why is the build failing")
    }

    @Test("the longer phrase wins") func longest() {
        #expect(CommandMatcher.match("New ticket for design: the empty state", in: commands)?
            .command.phrase == "new ticket for design")
    }

    @Test("a phrase in the middle of a sentence is not a command") func notMidSentence() {
        #expect(CommandMatcher.match("I will ask Claude about it later", in: commands) == nil)
        #expect(CommandMatcher.match("the new ticket process is broken", in: commands) == nil)
    }

    @Test("punctuation and case do not matter") func normalising() {
        #expect(CommandMatcher.match("ask claude: summarise this", in: commands)?.text == "summarise this")
        #expect(CommandMatcher.match("Remind me to, call the bank", in: commands)?.command.phrase == "remind me to")
    }

    @Test("a command that is turned off never matches") func disabled() {
        var off = commands
        off[0].enabled = false
        #expect(CommandMatcher.match("ask Claude what this means", in: off) == nil)
    }

    @Test("the phrase alone matches, with no text") func phraseOnly() {
        #expect(CommandMatcher.match("Ask Claude", in: commands)?.text == "")
    }
}

@MainActor
@Suite("Running a command") struct CommandRunnerTests {
    final class Fake: CommandPerforming, @unchecked Sendable {
        var performed: [(CommandAction, String)] = []
        var answer = "Done"
        var failure: (any Error)?
        func perform(_ action: CommandAction, text: String) async throws -> String {
            if let failure { throw failure }
            performed.append((action, text))
            return answer
        }
    }

    func rig(_ commands: [SpokenCommand]) -> (CommandRunner, Fake) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cmd-\(UUID().uuidString).json")
        let store = CommandStore(url: url)
        for command in store.commands { store.remove(command.id) }
        // Built-ins cannot be removed, so start from a file holding exactly these.
        try? JSONEncoder().encode(commands).write(to: url)
        let fresh = CommandStore(url: url)
        let fake = Fake()
        return (CommandRunner(store: fresh, performer: fake), fake)
    }

    @Test("a command that changes nothing runs straight away") func runsImmediately() async throws {
        let (runner, fake) = rig([SpokenCommand(phrase: "ask Claude",
                                                action: .openLink("https://claude.ai/new?q={text}"),
                                                confirm: false)])
        let message = try await runner.heard("ask Claude why the build failed")
        #expect(message == "Done")
        #expect(fake.performed.first?.1 == "why the build failed")
        #expect(runner.pending == nil)
    }

    @Test("a command that creates something waits to be confirmed") func waits() async throws {
        let (runner, fake) = rig([SpokenCommand(phrase: "remind me to", action: .reminder(list: "Ideas"))])
        let message = try await runner.heard("remind me to send the deck")
        #expect(message.contains("Add “send the deck” to your Ideas list"))
        #expect(fake.performed.isEmpty)             // nothing has happened yet
        #expect(try await runner.confirm() == "Done")
        #expect(fake.performed.count == 1)
        #expect(runner.pending == nil)
    }

    @Test("Esc drops what was waiting") func cancels() async throws {
        let (runner, fake) = rig([SpokenCommand(phrase: "remind me to", action: .reminder(list: ""))])
        _ = try await runner.heard("remind me to call the bank")
        #expect(runner.cancel())
        #expect(!runner.cancel())
        #expect(try await runner.confirm() == nil)
        #expect(fake.performed.isEmpty)
    }

    @Test("nothing matched says so, and does nothing") func noMatch() async {
        let (runner, fake) = rig([SpokenCommand(phrase: "ask Claude", action: .openApp("Claude"))])
        await #expect(throws: CommandError.noMatch("open the door")) {
            try await runner.heard("open the door")
        }
        #expect(fake.performed.isEmpty)
    }

    @Test("a command that needs words refuses without them") func needsText() async {
        let (runner, _) = rig([SpokenCommand(phrase: "remind me to", action: .reminder(list: ""))])
        await #expect(throws: CommandError.needsText("remind me to")) {
            try await runner.heard("remind me to")
        }
    }
}

@Suite("What a command will do") struct CommandActionTests {
    @Test("the link is filled in and encoded") func link() {
        let action = CommandAction.openLink("https://claude.ai/new?q={text}")
        #expect(action.describe(text: "why is it slow?").contains("why%20is%20it%20slow"))
    }

    @Test("actions that create something ask first by default") func defaults() {
        #expect(SpokenCommand(phrase: "a", action: .reminder(list: "")).confirm)
        #expect(SpokenCommand(phrase: "a", action: .notionPage(databaseID: "x")).confirm)
        #expect(!SpokenCommand(phrase: "a", action: .openLink("https://x")).confirm)
        #expect(!SpokenCommand(phrase: "a", action: .openApp("Notion")).confirm)
    }

    @Test("a command file written by an older build still loads") func decoding() throws {
        let json = #"[{"phrase":"ask Claude","action":{"openLink":{"_0":"https://claude.ai/new?q={text}"}}}]"#
        let commands = try JSONDecoder().decode([SpokenCommand].self, from: Data(json.utf8))
        #expect(commands.first?.phrase == "ask Claude")
        #expect(commands.first?.enabled == true)
    }

    @Test("the five that ship cover the five uses") func defaultsShipped() {
        let phrases = CommandStore.defaults.map(\.phrase)
        #expect(phrases == ["ask Claude", "remind me to", "capture idea", "new ticket", "deep work"])
        // The ones needing a detail only you have ship turned off, with the gap visible.
        let off = CommandStore.defaults.filter { !$0.enabled }.map(\.phrase)
        #expect(off == ["capture idea", "new ticket", "deep work"])
        #expect(CommandStore.defaults.allSatisfy { !$0.note.isEmpty })
    }
}

import AppKit
import SwiftUI

@MainActor
@Suite("Commands proof") struct CommandsProofTests {
    @Test("commands proof", .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF_COMMANDS"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF_COMMANDS"]!)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cmd-\(UUID().uuidString).json")
        let model = CommandsViewModel(store: CommandStore(url: url))
        model.appearance = .dark
        model.tryText = "remind me to send the deck to Salla"
        model.editing = model.commands.first { $0.phrase == "capture idea" }?.id
        let host = NSHostingView(rootView: CommandsView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 900)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: out)
    }
}
