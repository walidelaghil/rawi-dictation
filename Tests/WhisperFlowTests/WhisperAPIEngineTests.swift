import Testing
import Foundation
@testable import WhisperFlowCore

@Suite("WhisperAPIEngine") struct WhisperAPIEngineTests {
    @Test("multipart body carries every part with correct boundaries") func body() {
        let d = WhisperAPIEngine.multipartBody(boundary: "BOUND", model: "whisper-1",
                                               filename: "a.wav", wav: Data([1, 2, 3]))
        let s = String(decoding: d, as: UTF8.self)
        #expect(s.contains("--BOUND\r\n"))
        #expect(s.contains(#"name="model""#))
        #expect(s.contains("whisper-1"))
        #expect(s.contains(#"name="response_format""#))
        #expect(s.contains(#"name="file"; filename="a.wav""#))
        #expect(s.contains("Content-Type: audio/wav"))
        #expect(s.hasSuffix("--BOUND--\r\n"))
    }

    @Test("endpoints match each provider") func endpoints() {
        #expect(WhisperAPIEngine.endpoint(for: .groq).host == "api.groq.com")
        #expect(WhisperAPIEngine.endpoint(for: .openai).host == "api.openai.com")
    }

    @Test("parses the text field") func parse() throws {
        #expect(try WhisperAPIEngine.parseResponse(Data(#"{"text":"hello"}"#.utf8)) == "hello")
    }

    @Test("an error payload throws rather than returning empty") func parseError() {
        #expect(throws: (any Error).self) {
            try WhisperAPIEngine.parseResponse(Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
    }

    @Test("extracts a provider error message") func errorMessage() throws {
        #expect(try WhisperAPIEngine.errorMessage(
            Data(#"{"error":{"message":"invalid_api_key"}}"#.utf8)) == "invalid_api_key")
    }

    @Test("the factory refuses a provider with no key rather than failing later") func factory() {
        var config = Config.default
        config.engine = .groq
        #expect(throws: TranscriptionError.missingAPIKey("GROQ_API_KEY")) {
            _ = try TranscriptionEngineFactory.make(config: config, env: DotEnv(contents: ""))
        }
    }

    @Test("the factory builds a local engine without any key") func localFactory() throws {
        let e = try TranscriptionEngineFactory.make(config: .default, env: DotEnv(contents: ""))
        #expect(e is WhisperCppEngine)
    }
}
