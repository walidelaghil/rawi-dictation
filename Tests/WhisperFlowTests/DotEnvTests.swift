import Testing
@testable import WhisperFlowCore

@Suite("DotEnv") struct DotEnvTests {
    @Test("parses plain, quoted, exported and commented lines") func parses() {
        let env = DotEnv(contents: """
        # a comment
        OPENAI_API_KEY=sk-plain

        export ANTHROPIC_API_KEY="sk-quoted value"
        GROQ_API_KEY='sk-single'
        MALFORMED
        """)
        #expect(env["OPENAI_API_KEY"] == "sk-plain")
        #expect(env["ANTHROPIC_API_KEY"] == "sk-quoted value")
        #expect(env["GROQ_API_KEY"] == "sk-single")
        #expect(env["MALFORMED"] == nil)
        #expect(env["# a comment"] == nil)
    }

    @Test("trims surrounding whitespace but preserves inner") func trims() {
        let env = DotEnv(contents: "  KEY  =  a b  ")
        #expect(env["KEY"] == "a b")
    }

    @Test("exposes the set of keys present") func keys() {
        let env = DotEnv(contents: "A=1\nB=2")
        #expect(env.keys == ["A", "B"])
    }
}
