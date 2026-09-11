import Testing
import Foundation
@testable import RawiCore

final class SpyCleanup: CleanupProvider, @unchecked Sendable {
    let name: String
    var calls: [String] = []
    var cancels = 0
    var result: Result<String, any Error> = .success("cleaned")
    init(name: String) { self.name = name }
    func clean(_ t: String) async throws -> String { calls.append(t); return try result.get() }
    func cancel() { cancels += 1 }
}

@Suite("RoutedCleanup") struct RoutedCleanupTests {
    let models = CleanupModels(latin: "small-model", arabic: "big-model")

    func rig() -> (RoutedCleanup, [String: SpyCleanup]) {
        let spies = ["small-model": SpyCleanup(name: "small-model"),
                     "big-model": SpyCleanup(name: "big-model")]
        let r = RoutedCleanup(kind: .ollama, apiKey: nil, models: models, prompt: "P",
                              makeProvider: { spies[$0]! })
        return (r, spies)
    }

    @Test("english goes to the small model") func english() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("ship the release on Friday")
        #expect(spies["small-model"]!.calls.count == 1)
        #expect(spies["big-model"]!.calls.isEmpty)
    }

    @Test("arabic goes to the arabic-capable model") func arabic() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("يعني أعتقد أنه لازم نأجل الاجتماع")
        #expect(spies["big-model"]!.calls.count == 1)
        #expect(spies["small-model"]!.calls.isEmpty)
    }

    @Test("mixed arabic and english goes to the arabic model") func mixed() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("يعني الـ API مو شغال، لازم نسوي deploy")
        #expect(spies["big-model"]!.calls.count == 1)
    }

    @Test("the chosen model is inspectable without running it") func choice() {
        let (r, _) = rig()
        #expect(r.model(for: "hello there") == "small-model")
        #expect(r.model(for: "مرحبا كيف حالك") == "big-model")
    }

    @Test("a provider is built once per model and reused") func reuse() async throws {
        let spies = ["small-model": SpyCleanup(name: "s"), "big-model": SpyCleanup(name: "b")]
        let box = BuiltBox()
        let r = RoutedCleanup(kind: .ollama, apiKey: nil, models: models, prompt: "P",
                              makeProvider: { box.append($0); return spies[$0]! })
        _ = try await r.clean("one two three")
        _ = try await r.clean("four five six")
        #expect(box.names == ["small-model"])
    }

    @Test("cancel reaches whichever child ran") func cancels() async throws {
        let (r, spies) = rig()
        _ = try await r.clean("يعني تمام")
        r.cancel()
        #expect(spies["big-model"]!.cancels == 1)
        #expect(spies["small-model"]!.cancels == 0)
    }

    @Test("an empty transcript is returned without building anything") func empty() async throws {
        let box = BuiltBox()
        let r = RoutedCleanup(kind: .ollama, apiKey: nil, models: models, prompt: "P",
                              makeProvider: { box.append($0); return SpyCleanup(name: "x") })
        #expect(try await r.clean("   ") == "   ")
        #expect(box.names.isEmpty)
    }

    @Test("the factory returns a routed provider for every live kind") func factory() throws {
        var c = Config.default
        c.cleanup.provider = .ollama
        #expect(try CleanupProviderFactory.make(config: c, env: DotEnv(contents: "")) is RoutedCleanup)
        c.cleanup.provider = .off
        #expect(try CleanupProviderFactory.make(config: c, env: DotEnv(contents: "")) is NoopCleanup)
    }

    @Test("default models pair the benchmarked winners for local cleanup") func defaults() {
        let m = CleanupProviderFactory.defaultModels(for: .ollama)
        #expect(m.latin == "qwen2.5:1.5b")
        #expect(m.arabic == "qwen2.5:3b")
    }
}

final class BuiltBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _names: [String] = []
    var names: [String] { lock.withLock { _names } }
    func append(_ n: String) { lock.withLock { _names.append(n) } }
}
