import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("Cleanup") struct CleanupTests {
    @Test("noop returns its input unchanged") func noop() async throws {
        #expect(try await NoopCleanup().clean("  um so yeah  ") == "  um so yeah  ")
    }

    @Test("openai body uses a system role message") func openaiBody() throws {
        let d = try ChatCleanup.requestBody(kind: .openai, model: "gpt-4o-mini",
                                            prompt: "PROMPT", transcript: "TEXT")
        let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        let msgs = j["messages"] as! [[String: String]]
        #expect(msgs[0]["role"] == "system")
        #expect(msgs[0]["content"] == "PROMPT")
        #expect(msgs[1]["role"] == "user")
        #expect(msgs[1]["content"] == "TEXT")
        #expect(j["model"] as? String == "gpt-4o-mini")
    }

    @Test("anthropic body uses a top-level system field") func anthropicBody() throws {
        let d = try ChatCleanup.requestBody(kind: .anthropic, model: "claude-haiku-4-5-20251001",
                                            prompt: "PROMPT", transcript: "TEXT")
        let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        #expect(j["system"] as? String == "PROMPT")
        #expect(j["max_tokens"] != nil)
        let msgs = j["messages"] as! [[String: Any]]
        #expect(msgs.count == 1)
        #expect(msgs[0]["role"] as? String == "user")
    }

    @Test("ollama body disables streaming") func ollamaBody() throws {
        let d = try ChatCleanup.requestBody(kind: .ollama, model: "qwen2.5:3b",
                                            prompt: "P", transcript: "T")
        let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        #expect(j["stream"] as? Bool == false)
    }

    @Test("every provider asks for deterministic output") func temperature() throws {
        for kind in [CleanupKind.openai, .ollama] {
            let d = try ChatCleanup.requestBody(kind: kind, model: "m", prompt: "P", transcript: "T")
            let j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
            let temp = (j["temperature"] as? Int) ?? ((j["options"] as? [String: Any])?["temperature"] as? Int)
            #expect(temp == 0)
        }
    }

    @Test("each provider response shape parses") func parsing() throws {
        #expect(try ChatCleanup.parse(kind: .openai,
            Data(#"{"choices":[{"message":{"content":"A"}}]}"#.utf8)) == "A")
        #expect(try ChatCleanup.parse(kind: .anthropic,
            Data(#"{"content":[{"type":"text","text":"B"}]}"#.utf8)) == "B")
        #expect(try ChatCleanup.parse(kind: .ollama,
            Data(#"{"message":{"content":"C"}}"#.utf8)) == "C")
    }

    @Test("anthropic parsing skips non-text content blocks") func anthropicThinking() throws {
        let json = #"{"content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"B"}]}"#
        #expect(try ChatCleanup.parse(kind: .anthropic, Data(json.utf8)) == "B")
    }

    @Test("a malformed response throws") func badParse() {
        #expect(throws: (any Error).self) {
            try ChatCleanup.parse(kind: .openai, Data(#"{"choices":[]}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try ChatCleanup.parse(kind: .ollama, Data(#"{}"#.utf8))
        }
    }

    @Test("endpoints are correct per provider") func endpoints() {
        #expect(ChatCleanup.endpoint(kind: .ollama).absoluteString
                == "http://localhost:11434/api/chat")
        #expect(ChatCleanup.endpoint(kind: .anthropic).path == "/v1/messages")
        #expect(ChatCleanup.endpoint(kind: .openai).path == "/v1/chat/completions")
    }

    @Test("the factory refuses a keyless api provider") func factoryNoKey() {
        var config = Config.default
        config.cleanup.provider = .anthropic
        #expect(throws: CleanupError.missingAPIKey("ANTHROPIC_API_KEY")) {
            _ = try CleanupProviderFactory.make(config: config, env: DotEnv(contents: ""))
        }
    }

    @Test("the factory builds ollama and off without any key") func factoryKeyless() throws {
        var config = Config.default
        config.cleanup.provider = .ollama
        #expect(try CleanupProviderFactory.make(config: config, env: DotEnv(contents: "")) is ChatCleanup)
        config.cleanup.provider = .off
        #expect(try CleanupProviderFactory.make(config: config, env: DotEnv(contents: "")) is NoopCleanup)
    }

    @Test("an empty transcript is returned without a network call") func emptyShortCircuit() async throws {
        let c = ChatCleanup(kind: .openai, apiKey: "unused", model: "m", prompt: "P")
        #expect(try await c.clean("   ") == "   ")
    }
}
