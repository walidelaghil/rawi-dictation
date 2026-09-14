import Testing
@testable import RawiCore

@Suite("SnippetExpander") struct SnippetExpanderTests {
    let email = Snippet(trigger: "my email", expansion: "rawi@example.com")
    let work = Snippet(trigger: "my work email", expansion: "rawi@example.org")
    let sig = Snippet(trigger: "توقيعي", expansion: "مع التحية، وليد")

    @Test("expands a trigger mid-sentence") func expands() {
        #expect(SnippetExpander.expand("Send it to my email please", with: [email])
                == "Send it to rawi@example.com please")
    }

    @Test("is case-insensitive") func caseInsensitive() {
        #expect(SnippetExpander.expand("My Email is there", with: [email])
                .contains("rawi@example.com"))
    }

    @Test("tolerates the punctuation cleanup adds") func punctuation() {
        #expect(SnippetExpander.expand("Use my email.", with: [email])
                == "Use rawi@example.com.")
    }

    @Test("the longest trigger wins") func longest() {
        // "my work email" must beat "my email", or the specific one never fires.
        let out = SnippetExpander.expand("Use my work email today", with: [email, work])
        #expect(out.contains("rawi@example.org"))
        #expect(!out.contains("gmail"))
    }

    @Test("does not match inside a word") func wordBoundary() {
        let s = Snippet(trigger: "sig", expansion: "SIGNATURE")
        #expect(SnippetExpander.expand("the design is signed", with: [s])
                == "the design is signed")
    }

    @Test("expansion is single pass, so a self-referential snippet cannot loop") func noLoop() {
        // If expansions were re-scanned this would never terminate.
        let s = Snippet(trigger: "loop", expansion: "loop and loop")
        #expect(SnippetExpander.expand("start loop end", with: [s]) == "start loop and loop end")
    }

    @Test("Arabic triggers expand") func arabic() {
        #expect(SnippetExpander.expand("شكرا توقيعي", with: [sig]).contains("مع التحية"))
    }

    @Test("no snippets leaves the text untouched") func none() {
        #expect(SnippetExpander.expand("nothing to do here", with: []) == "nothing to do here")
    }

    @Test("multiple occurrences all expand") func repeated() {
        let s = Snippet(trigger: "ack", expansion: "acknowledged")
        #expect(SnippetExpander.expand("ack and ack", with: [s]) == "acknowledged and acknowledged")
    }

    @Test("empty text is returned as is") func emptyText() {
        #expect(SnippetExpander.expand("", with: [email]) == "")
    }
}
