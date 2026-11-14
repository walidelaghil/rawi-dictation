import Testing
import Foundation
@testable import RawiCore

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
        var config = Config.default
        config.engine = .whispercpp
        let e = try TranscriptionEngineFactory.make(config: config, env: DotEnv(contents: ""))
        // Resident by default now: the CLI reloaded the model on every dictation.
        #expect(e is WhisperServerEngine)
        var cliConfig = config
        cliConfig.whispercpp.useServer = false
        #expect(try TranscriptionEngineFactory.make(config: cliConfig, env: DotEnv(contents: ""))
                is WhisperCppEngine)
    }
}
