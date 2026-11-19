import Testing
@testable import RawiCore

@Suite("English restore stage") struct EnglishRestoreTests {
    @Test("a guarded swap from the model is used")
    func used() async {
        let model = FakeCleanup()
        model.result = .success("أبغى أسوي meeting مع الفريق")
        let out = await EnglishRestore.apply("أبغى أسوي ميتنغ مع الفريق", using: model)
        #expect(out == "أبغى أسوي meeting مع الفريق")
        #expect(model.received == ["أبغى أسوي ميتنغ مع الفريق"])
    }

    @Test("a result the guard rejects keeps the original")
    func rejected() async {
        let model = FakeCleanup()
        model.result = .success("I want a meeting with the team")
        let original = "أبغى أسوي ميتنغ مع الفريق"
        #expect(await EnglishRestore.apply(original, using: model) == original)
    }

    @Test("a model error keeps the original")
    func failed() async {
        let model = FakeCleanup()
        model.result = .failure(CleanupError.cancelled)
        let original = "أبغى أسوي ميتنغ"
        #expect(await EnglishRestore.apply(original, using: model) == original)
    }

    @Test("text with no Arabic is never sent to the model")
    func noArabic() async {
        let model = FakeCleanup()
        let original = "We need to talk about the project."
        #expect(await EnglishRestore.apply(original, using: model) == original)
        #expect(model.received.isEmpty)
    }

    @Test("a model that takes too long is abandoned and the original is kept")
    func slow() async {
        let model = FakeCleanup()
        model.result = .success("أبغى meeting")
        model.delay = .seconds(5)
        let original = "أبغى ميتنغ"
        let start = ContinuousClock.now
        let out = await EnglishRestore.apply(original, using: model, timeout: .milliseconds(200))
        #expect(out == original)
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}
