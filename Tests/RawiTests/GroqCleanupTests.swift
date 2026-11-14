import Foundation
import Testing
@testable import RawiCore

@Suite("Cleanup through Groq") struct GroqCleanupTests {
    @Test("the request is OpenAI-shaped, to Groq, without thinking time") func request() throws {
        #expect(ChatCleanup.endpoint(kind: .groq).host == "api.groq.com")
        let body = try ChatCleanup.requestBody(kind: .groq, model: "qwen/qwen3.8-27b",
                                               prompt: "P", user: "U")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["reasoning_effort"] as? String == "none")
        #expect((json["messages"] as? [[String: String]])?.first?["content"] == "P")
        let gpt = try ChatCleanup.requestBody(kind: .groq, model: "openai/gpt-oss-120b",
                                              prompt: "P", user: "U")
        #expect((try JSONSerialization.jsonObject(with: gpt) as? [String: Any])?["reasoning_effort"]
                as? String == "low")
        #expect(ChatCleanup.timeout(for: .groq) < 10)
    }

    @Test("one Arabic word sends the whole dictation to the Arabic model") func routing() {
        let r = RoutedCleanup(kind: .groq, apiKey: "k",
                              models: CleanupProviderFactory.defaultModels(for: .groq), prompt: "P")
        #expect(r.model(for: "ship the release on Friday") == "qwen/qwen3.8-27b")
        #expect(r.model(for: "they liked the demo بس they want the pricing by Sunday")
                == "openai/gpt-oss-120b")
        // Local models keep the ratio: there, the big model costs seconds.
        let local = RoutedCleanup(kind: .ollama, apiKey: nil,
                                  models: CleanupModels(latin: "s", arabic: "b"), prompt: "P")
        #expect(local.model(for: "they liked the demo بس they want the pricing by Sunday") == "s")
    }

    @Test("polish routes by script on Groq, and needs the key") func polisher() throws {
        var config = Config.default
        config.cleanup.provider = .groq
        config.cleanup.mode = .polish
        config.cleanup.models = CleanupProviderFactory.defaultModels(for: .groq)
        let env = DotEnv(contents: "GROQ_API_KEY=k")
        let polisher = try CleanupProviderFactory.makePolisher(config: config, env: env)
        #expect((polisher as? RoutedCleanup)?.model(for: "مرحبا") == "openai/gpt-oss-120b")
        #expect(throws: CleanupError.self) {
            try CleanupProviderFactory.make(config: config, env: DotEnv(contents: ""))
        }
    }
}
