import Testing
import Foundation
@testable import RawiCore

@Suite("Installed models") struct OllamaModelsTests {
    @Test("names are read out of the tags response") func parse() {
        let json = """
            {"models":[{"name":"qwen2.5:3b","size":1929912432},\
            {"name":"gemma3:4b","size":3338801804},{"name":"qwen2.5:1.5b","size":986000000}]}
            """
        #expect(OllamaModels.parse(Data(json.utf8))
                == ["gemma3:4b", "qwen2.5:1.5b", "qwen2.5:3b"])
    }

    @Test("anything that is not a tags response yields nothing, never a crash") func junk() {
        #expect(OllamaModels.parse(Data("not json".utf8)).isEmpty)
        #expect(OllamaModels.parse(Data("{}".utf8)).isEmpty)
        #expect(OllamaModels.parse(Data(#"{"models":[{"size":1}]}"#.utf8)).isEmpty)
    }

    @Test("the two this app was tuned against come first") func ordering() {
        #expect(OllamaModels.preferred(from: ["gemma3:4b", "qwen2.5:1.5b", "qwen2.5:3b"])
                == ["qwen2.5:1.5b", "qwen2.5:3b", "gemma3:4b"])
        // Not installed, not offered.
        #expect(OllamaModels.preferred(from: ["gemma3:4b"]) == ["gemma3:4b"])
    }
}
