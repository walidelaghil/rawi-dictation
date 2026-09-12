import Testing
import Foundation
@testable import RawiCore

private final class FakeClipboard: ClipboardAccess, @unchecked Sendable {
    var text: String?
    init(_ text: String?) { self.text = text }
}

private final class FakeRewriter: CleanupProvider, @unchecked Sendable {
    var received: [String] = []
    var reply: String = "rewritten"
    var failure: (any Error)?
    func clean(_ text: String, instruction: String) async throws -> String {
        received.append(text)
        if let failure { throw failure }
        return reply
    }
    func cancel() {}
}

@MainActor
@Suite("TransformRunner") struct TransformRunnerTests {
    func store() -> TransformStore {
        TransformStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-tr-\(UUID().uuidString).json"))
    }

    @Test("an empty clipboard is refused before the model is ever called") func empty() async {
        let clip = FakeClipboard("   \n "), model = FakeRewriter()
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        await #expect(throws: TransformError.emptyClipboard) {
            try await runner.run(spoken: "make it shorter")
        }
        #expect(model.received.isEmpty)
        #expect(clip.text == "   \n ")
    }

    @Test("a named transform contributes its tuned instruction") func named() async throws {
        let clip = FakeClipboard("a long rambling paragraph"), model = FakeRewriter()
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        let outcome = try await runner.run(spoken: "make it shorter")
        #expect(outcome.transform?.name == "Make it shorter")
        #expect(model.received.first?.contains("Cut this to its essential message") == true)
        #expect(model.received.first?.contains("<text>a long rambling paragraph</text>") == true)
    }

    @Test("an unmatched instruction is sent as spoken") func verbatim() async throws {
        let clip = FakeClipboard("some notes"), model = FakeRewriter()
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        let outcome = try await runner.run(spoken: "rewrite this as a haiku")
        #expect(outcome.transform == nil)
        #expect(model.received.first?.contains("<instruction>rewrite this as a haiku</instruction>")
                == true)
    }

    @Test("success replaces the clipboard") func writes() async throws {
        let clip = FakeClipboard("before"), model = FakeRewriter()
        model.reply = "after"
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        _ = try await runner.run(spoken: "polish")
        #expect(clip.text == "after")
    }

    @Test("a failed transform leaves the clipboard exactly as it was") func failure() async {
        let clip = FakeClipboard("precious original"), model = FakeRewriter()
        model.failure = CleanupError.badResponse("ollama is not running")
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        await #expect(throws: (any Error).self) { try await runner.run(spoken: "polish") }
        #expect(clip.text == "precious original")
    }

    @Test("an empty rewrite is refused rather than written") func emptyReply() async {
        let clip = FakeClipboard("precious original"), model = FakeRewriter()
        model.reply = "  \n"
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        await #expect(throws: TransformError.emptyResult) {
            try await runner.run(spoken: "polish")
        }
        #expect(clip.text == "precious original")
    }

    @Test("the original reaches history before the model runs, even if it then fails")
    func originalFirst() async {
        let clip = FakeClipboard("precious original"), model = FakeRewriter()
        model.failure = CleanupError.badResponse("down")
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        var seen: [String] = []
        runner.onOriginal = { seen.append($0) }
        _ = try? await runner.run(spoken: "polish")
        #expect(seen == ["precious original"])
    }

    @Test("the cleanup guard is not applied — a transform is supposed to change the text")
    func noGuard() async throws {
        // CleanupGuard would reject this outright: 5 words become 1.
        let clip = FakeClipboard("the quick brown fox jumps"), model = FakeRewriter()
        model.reply = "Fox."
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        let outcome = try await runner.run(spoken: "make it shorter")
        #expect(outcome.after == "Fox.")
        #expect(clip.text == "Fox.")
    }

    @Test("the clipboard text is trimmed of the stray newline a copy leaves behind")
    func trims() async throws {
        let clip = FakeClipboard("  hello  \n"), model = FakeRewriter()
        let runner = TransformRunner(store: store(), rewriter: model, clipboard: clip)
        let outcome = try await runner.run(spoken: "polish")
        #expect(outcome.before == "hello")
    }
}

@Suite("Transform wire format") struct TransformWireTests {
    @Test("a transform is sent under its own system prompt, not the cleaner's")
    func systemPrompt() throws {
        // The cleaner's prompt forbids rewriting; sending a transform under it
        // would make the model refuse the one thing it is being asked to do.
        let d = try ChatCleanup.requestBody(
            kind: .ollama, model: "m", prompt: transformSystemPrompt,
            user: wrapTransform(text: "T", instruction: "shorten"))
        let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        let msgs = j["messages"] as! [[String: Any]]
        #expect((msgs[0]["content"] as? String)?.contains("You rewrite text on request") == true)
        #expect(msgs.last?["content"] as? String
                == "<instruction>shorten</instruction>\n<text>T</text>")
    }

    @Test("the transform payload is not wrapped as a transcript") func noDoubleWrap() throws {
        let d = try ChatCleanup.requestBody(
            kind: .ollama, model: "m", prompt: transformSystemPrompt,
            user: wrapTransform(text: "T", instruction: "shorten"))
        #expect(String(data: d, encoding: .utf8)?.contains("transcript") == false)
    }
}

private final class SlowRewriter: CleanupProvider, @unchecked Sendable {
    func clean(_ text: String, instruction: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(40))
        return "rewritten"
    }
    func cancel() {}
}

@MainActor
@Suite("Transform through the controller") struct ControllerTransformTests {
    func rig(transcript: String) -> (DictationController, FakeInserter, FakeCleanup) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        e.result = .success(transcript)
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: l)
        return (ctl, i, c)
    }
    func store() -> TransformStore {
        TransformStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-ct-\(UUID().uuidString).json"))
    }

    @Test("a transform never types into the document") func neverInserts() async {
        let (ctl, inserter, cleanup) = rig(transcript: "make it shorter")
        let clip = FakeClipboard("a long paragraph")
        ctl.transformRunner = TransformRunner(store: store(), rewriter: FakeRewriter(),
                                              clipboard: clip)
        await ctl.handle(.beganHold, intent: .transform)
        await ctl.handle(.endedHold)
        #expect(inserter.inserted.isEmpty)
        // The cleanup provider is the *dictation* one: a transform must not run
        // the transcript through it.
        #expect(cleanup.received.isEmpty)
        #expect(clip.text == "rewritten")
    }

    @Test("the spoken words are the instruction, not the material") func spokenIsInstruction() async {
        let (ctl, _, _) = rig(transcript: "translate to arabic")
        let model = FakeRewriter()
        ctl.transformRunner = TransformRunner(store: store(), rewriter: model,
                                              clipboard: FakeClipboard("Ship it on Monday."))
        await ctl.handle(.beganHold, intent: .transform)
        await ctl.handle(.endedHold)
        #expect(model.received.first?.contains("<text>Ship it on Monday.</text>") == true)
        #expect(model.received.first?.contains("Modern Standard Arabic") == true)
    }

    @Test("the clipboard as it was reaches history") func historyFirst() async {
        let (ctl, _, _) = rig(transcript: "polish")
        var recorded: [HistoryEntry] = []
        ctl.onRecord = { recorded.append($0) }
        ctl.transformRunner = TransformRunner(store: store(), rewriter: FakeRewriter(),
                                              clipboard: FakeClipboard("the original"))
        await ctl.handle(.beganHold, intent: .transform)
        await ctl.handle(.endedHold)
        #expect(recorded.count == 1)
        #expect(recorded.first?.cleaned == "the original")
        #expect(recorded.first?.kind == .transform)
    }

    @Test("an empty clipboard says so and leaves nothing in history") func emptyClipboard() async {
        let (ctl, _, _) = rig(transcript: "polish")
        var recorded: [HistoryEntry] = []
        ctl.onRecord = { recorded.append($0) }
        ctl.transformRunner = TransformRunner(store: store(), rewriter: FakeRewriter(),
                                              clipboard: FakeClipboard(nil))
        await ctl.handle(.beganHold, intent: .transform)
        await ctl.handle(.endedHold)
        #expect(ctl.state == .error("Copy some text first"))
        #expect(recorded.isEmpty)
    }

    @Test("with no provider the transform key explains itself") func noProvider() async {
        let (ctl, _, _) = rig(transcript: "polish")
        ctl.transformRunner = nil
        await ctl.handle(.beganHold, intent: .transform)
        await ctl.handle(.endedHold)
        #expect(ctl.state == .error("Transforms need a cleanup provider"))
    }

    @Test("the pill shows rewriting while the model works") func transformingState() async {
        let (ctl, _, _) = rig(transcript: "polish")
        ctl.transformRunner = TransformRunner(store: store(), rewriter: SlowRewriter(),
                                              clipboard: FakeClipboard("text"))
        var seen: [DictationState] = []
        ctl.onStateChange = { seen.append($0) }
        await ctl.handle(.beganHold, intent: .transform)
        await ctl.handle(.endedHold)
        #expect(seen.contains(.transforming))
        #expect(!seen.contains(.cleaning))          // a transform is not a cleanup
        #expect(!seen.contains(.inserting))
        #expect(ctl.state == .notice("Rewritten — press ⌘V"))
    }

    @Test("a double-tapped transform key is still a transform") func doubleTapKeepsIntent() async {
        let (ctl, inserter, _) = rig(transcript: "polish")
        let clip = FakeClipboard("text")
        ctl.transformRunner = TransformRunner(store: store(), rewriter: FakeRewriter(),
                                              clipboard: clip)
        await ctl.handle(.beganDoubleTap, intent: .transform)
        await ctl.handle(.stopHandsFree)
        #expect(clip.text == "rewritten")
        #expect(inserter.inserted.isEmpty)
    }
}
