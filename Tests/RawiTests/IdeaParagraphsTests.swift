import Foundation
import Testing
@testable import RawiCore

private struct FixedPlanner: ParagraphPlanner {
    var starts: [Int] = []
    var delay: Duration = .zero
    var fails = false
    func paragraphStarts(_ sentences: [String]) async throws -> [Int] {
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw IdeaParagraphs.PlanError.badResponse("boom") }
        return starts
    }
}

/// Four ideas, no announcement of any of them: what a real long dictation is like.
let fourIdeas = "Okay so a few updates from today. I met with the design team this "
    + "morning and we agreed to drop the dark mode toggle. We'll revisit it after "
    + "launch. On the hiring side, we have two strong candidates for the backend "
    + "role. Please schedule second interviews before Friday. I need the October "
    + "numbers by Wednesday for the investor update. Thanks."

@Suite("One paragraph per idea") struct IdeaParagraphsTests {
    @Test("the planned breaks become blank lines, and every word survives") func breaks() async throws {
        let ideas = try #require(try await IdeaParagraphs.plan(
            fourIdeas, using: FixedPlanner(starts: [2, 4, 6, 7])))
        #expect(ideas.count == 5)
        #expect(ideas[1].hasPrefix("I met with the design team"))
        #expect(ideas[2].hasPrefix("On the hiring side"))
        #expect(ideas.last == "Thanks.")
        let formatted = SpokenStructure.format(fourIdeas, ideas: ideas)
        #expect(formatted.replacingOccurrences(of: "\n\n", with: " ") == fourIdeas)
    }

    @Test("nonsense from the model gives no breaks, not wrong ones") func nonsense() {
        let sentences = ["A.", "B.", "C."]
        #expect(IdeaParagraphs.apply(starts: [0, 1, -3, 99], to: sentences) == ["A. B. C."])
        #expect(IdeaParagraphs.apply(starts: [3, 3, 2], to: sentences) == ["A.", "B.", "C."])
    }

    @Test("a short dictation is never sent") func short() {
        #expect(!IdeaParagraphs.worthPlanning("One sentence. Two. Three. Four."))
        #expect(!IdeaParagraphs.worthPlanning(String(repeating: "word ", count: 80)))
        #expect(IdeaParagraphs.worthPlanning(fourIdeas))
        #expect(!IdeaParagraphs.worthPlanning(fourIdeas + "\nAlready shaped."))
    }

    @Test("a slow model costs the paragraphs, not the wait") func deadline() async {
        let began = ContinuousClock.now
        await #expect(throws: IdeaParagraphs.PlanError.self) {
            try await IdeaParagraphs.plan(fourIdeas,
                                          using: FixedPlanner(starts: [3], delay: .seconds(5)),
                                          deadline: .milliseconds(100))
        }
        #expect(began.duration(to: .now) < .seconds(1))
    }

    @Test("a spoken list stays a list") func listWins() {
        let spoken = "There are three things to do this week before the launch. "
            + "First write the release notes, second review them with the team, "
            + "third publish them on the blog. After that we can relax a bit and "
            + "plan the next quarter properly with everyone."
        let ideas = IdeaParagraphs.apply(starts: [2, 3],
                                         to: SpokenParagraphs.sentencesOf(spoken))
        #expect(SpokenStructure.format(spoken, ideas: ideas) == SpokenStructure.format(spoken))
    }

    @Test("the request numbers the sentences and asks for JSON") func request() throws {
        let data = try GroqParagraphPlanner.requestBody(model: "qwen/qwen3.8-27b",
                                                        sentences: ["Hi.", "Bye."])
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["reasoning_effort"] as? String == "none")
        #expect(body["temperature"] as? Int == 0)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages[1]["content"] == "1. Hi.\n2. Bye.")
    }

    @Test("the answer is read from the chat response") func parse() throws {
        let reply = #"{"choices":[{"message":{"content":"{\"starts\": [2, 5]}"}}]}"#
        #expect(try GroqParagraphPlanner.parse(Data(reply.utf8)) == [2, 5])
        #expect(throws: IdeaParagraphs.PlanError.self) {
            try GroqParagraphPlanner.parse(Data(#"{"choices":[]}"#.utf8))
        }
    }

    @Test("settings default on and survive an old config") func config() throws {
        let old = #"{"restorePreviousClipboard": true, "restoreDelayMs": 300}"#
        let output = try JSONDecoder().decode(OutputSettings.self, from: Data(old.utf8))
        #expect(output.ideaParagraphs)
        #expect(output.formatSpokenLists)
        let api = try JSONDecoder().decode(APISettings.self,
                                           from: Data(#"{"groqModel": "x"}"#.utf8))
        #expect(api.groqParagraphModel == GroqParagraphPlanner.defaultModel)
    }
}

@MainActor
@Suite("Paragraphs in a real dictation") struct IdeaParagraphsControllerTests {
    func run(planner: (any ParagraphPlanner)?) async -> String? {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        e.result = .success(fourIdeas)
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: l)
        ctl.paragraphPlanner = planner
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        return i.inserted.last
    }

    @Test("a long dictation is pasted in paragraphs") func pasted() async throws {
        let text = try #require(await run(planner: FixedPlanner(starts: [2, 4])))
        #expect(text.components(separatedBy: "\n\n").count == 3)
    }

    @Test("a failed plan pastes the words as one block") func failed() async throws {
        let text = try #require(await run(planner: FixedPlanner(fails: true)))
        #expect(!text.contains("\n"))
        #expect(text.contains("On the hiring side"))
    }
}

/// Against Groq itself, with the key in ~/.config/rawi/.env:
///
///     RAWI_LIVE_PARAGRAPHS=1 swift test --filter IdeaParagraphsLive
@Suite("Paragraphs, live", .enabled(if: ProcessInfo.processInfo.environment["RAWI_LIVE_PARAGRAPHS"] != nil))
struct IdeaParagraphsLiveTests {
    @Test func realModel() async throws {
        let key = try #require(DotEnv.load(from: Config.envFile)["GROQ_API_KEY"])
        let planner = GroqParagraphPlanner(apiKey: key)
        let arabic = "كنت أفكر في خطة المنتج للربع القادم، وهناك بعض الأشياء التي أريد كتابتها قبل الاجتماع غدا. "
            + "عملية التسجيل ما زالت طويلة جدا، والناس يتركون التطبيق عند الشاشة الثالثة. "
            + "صفحة الأسعار تحتاج إلى مقارنة أوضح بين الخطط، لأن فريق الدعم يجيب على نفس السؤال خمس مرات في اليوم. "
            + "أريد ملخصا قصيرا من كل قائد فريق يوم الخميس حتى نتفق على الأولويات. شكرا للجميع."
        for text in [fourIdeas, arabic] {
            let began = ContinuousClock.now
            let ideas = try #require(try await IdeaParagraphs.plan(text, using: planner))
            print("LIVE \(began.duration(to: .now).milliseconds)ms, \(ideas.count) paragraphs:\n"
                  + SpokenStructure.format(text, ideas: ideas) + "\n")
            #expect(ideas.count >= 3)
        }
    }
}
