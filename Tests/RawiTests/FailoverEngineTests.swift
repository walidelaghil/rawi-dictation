import Foundation
import Testing
@testable import RawiCore

private final class StubEngine: TranscriptionEngine, @unchecked Sendable {
    enum Behaviour { case answer(String), fail(Error), hang }
    let lock = NSLock()
    var behaviour: Behaviour
    var calls = 0
    var prefetches = 0
    init(_ b: Behaviour) { behaviour = b }

    func transcribe(wav: URL, prompt: String) async throws -> String {
        let b = lock.withLock { calls += 1; return behaviour }
        switch b {
        case .answer(let s): return s
        case .fail(let e): throw e
        case .hang:
            try await Task.sleep(for: .seconds(30))
            return "too late"
        }
    }
    func cancel() {}
    func prefetch() { lock.withLock { prefetches += 1 } }
}

private func wav() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("failover-\(UUID().uuidString).wav")
    let w = try WAVWriter(url: url)
    try w.append([Int16](repeating: 100, count: 16_000))
    try w.finalize()
    return url
}

@Suite struct FailoverEngineTests {
    @Test func cloudAnswersAndLocalIsNeverTouched() async throws {
        let cloud = StubEngine(.answer("cloud")), local = StubEngine(.answer("local"))
        let engine = FailoverEngine(primary: cloud, fallback: local, log: SilentLog())
        #expect(try await engine.transcribe(wav: try wav(), prompt: "") == "cloud")
        #expect(local.calls == 0)
    }

    @Test func networkFailureFallsBackAndSkipsCloudForAWhile() async throws {
        let cloud = StubEngine(.fail(TranscriptionError.apiError(status: 0, message: "offline")))
        let local = StubEngine(.answer("local"))
        let engine = FailoverEngine(primary: cloud, fallback: local, log: SilentLog())
        #expect(try await engine.transcribe(wav: try wav(), prompt: "") == "local")
        #expect(try await engine.transcribe(wav: try wav(), prompt: "") == "local")
        #expect(cloud.calls == 1)              // offline costs one attempt, not one per dictation
    }

    @Test func cloudIsTriedAgainAfterTheCooldown() async throws {
        let cloud = StubEngine(.fail(TranscriptionError.apiError(status: 500, message: "down")))
        let local = StubEngine(.answer("local"))
        let engine = FailoverEngine(primary: cloud, fallback: local, log: SilentLog(),
                                    cooldown: .milliseconds(50))
        _ = try await engine.transcribe(wav: try wav(), prompt: "")
        try await Task.sleep(for: .milliseconds(80))
        cloud.lock.withLock { cloud.behaviour = .answer("cloud") }
        #expect(try await engine.transcribe(wav: try wav(), prompt: "") == "cloud")
    }

    @Test func aHangingCloudIsAbandonedAtTheDeadline() async throws {
        let cloud = StubEngine(.hang), local = StubEngine(.answer("local"))
        let engine = FailoverEngine(primary: cloud, fallback: local, log: SilentLog(),
                                    deadline: { _ in .milliseconds(150) })
        let began = ContinuousClock.now
        #expect(try await engine.transcribe(wav: try wav(), prompt: "") == "local")
        #expect(began.duration(to: .now) < .seconds(2))
    }

    @Test func silenceIsNotRetriedLocally() async throws {
        let cloud = StubEngine(.fail(TranscriptionError.emptyResult))
        let local = StubEngine(.answer("hallucination"))
        let engine = FailoverEngine(primary: cloud, fallback: local, log: SilentLog())
        await #expect(throws: TranscriptionError.emptyResult) {
            try await engine.transcribe(wav: try wav(), prompt: "")
        }
        #expect(local.calls == 0)
    }

    @Test func escapeCancelsInsteadOfFallingBack() async throws {
        let cloud = StubEngine(.hang), local = StubEngine(.answer("local"))
        let engine = FailoverEngine(primary: cloud, fallback: local, log: SilentLog())
        let url = try wav()
        let task = Task { try await engine.transcribe(wav: url, prompt: "") }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(local.calls == 0)
    }

    /// Through the existential, as the controller calls it. Declared only in a
    /// protocol extension, this went to the no-op default and never ran.
    @Test func prefetchReachesTheEngineThroughTheProtocol() {
        let cloud = StubEngine(.answer("")), local = StubEngine(.answer(""))
        let engine: any TranscriptionEngine = FailoverEngine(primary: cloud, fallback: local,
                                                             log: SilentLog())
        engine.prefetch()
        #expect(cloud.prefetches == 1)
    }

    @Test func languageIsSentToTheProviderOnlyWhenKnown() {
        let api = WhisperAPIEngine(provider: .groq, apiKey: "k", model: "m", language: "auto")
        #expect(api.language == nil)
        api.use(language: .arabic)
        #expect(api.language == "ar")
        let body = String(decoding: WhisperAPIEngine.multipartBody(
            boundary: "B", model: "m", filename: "a.wav", wav: Data(), language: "ar"), as: UTF8.self)
        #expect(body.contains("name=\"language\"\r\n\r\nar"))
    }
}
