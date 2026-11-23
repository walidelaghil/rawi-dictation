import Testing
@testable import RawiCore

/// On the user's real mixed recording, Whisper and Deepgram both wrote English
/// words in Arabic letters (ميتنغ, ديمو, نوشن). A model is asked to put them back
/// into English letters; this guard is what makes that safe. It accepts a result
/// only if the *only* change is an Arabic-script token turned into a Latin one.
@Suite("English restore guard") struct EnglishRestoreGuardTests {
    @Test("an Arabic spelling of an English word becomes Latin")
    func accepts() {
        #expect(EnglishRestoreGuard.check(original: "أبغى أسوي ميتنغ مع الفريق",
                                          restored: "أبغى أسوي meeting مع الفريق") == .accept)
    }

    @Test("several swaps, punctuation kept")
    func severalSwaps() {
        #expect(EnglishRestoreGuard.check(original: "افتح نوشن، وكلم سارة عن الديمو.",
                                          restored: "افتح Notion، وكلم سارة عن demo.") == .accept)
    }

    @Test("identical text is accepted")
    func unchanged() {
        #expect(EnglishRestoreGuard.check(original: "كيف حالك اليوم", restored: "كيف حالك اليوم") == .accept)
    }

    @Test("a word translated to English is rejected")
    func translation() {
        // "الفريق" is Arabic for "the team"; turning it into "team" is a translation,
        // not a restored loanword. The guard cannot tell the two apart by itself,
        // so it limits what may change: only tokens the engine spelled in Arabic
        // that the model rewrote to Latin. A dropped or added token is the signal.
        #expect(EnglishRestoreGuard.check(original: "أبغى أسوي ميتنغ مع الفريق",
                                          restored: "I want a meeting with the team") != .accept)
    }

    @Test("a dropped word is rejected")
    func dropped() {
        #expect(EnglishRestoreGuard.check(original: "أبغى أسوي ميتنغ مع الفريق",
                                          restored: "أبغى meeting مع الفريق") != .accept)
    }

    @Test("an added word is rejected")
    func added() {
        #expect(EnglishRestoreGuard.check(original: "أسوي ميتنغ", restored: "أسوي a meeting") != .accept)
    }

    @Test("an Arabic word changed into another Arabic word is rejected")
    func arabicToArabic() {
        #expect(EnglishRestoreGuard.check(original: "أبغى أسوي ميتنغ", restored: "أريد أسوي meeting") != .accept)
    }

    @Test("a Latin word that was already right must not change")
    func latinChanged() {
        #expect(EnglishRestoreGuard.check(original: "أرسل الـ report بكرة", restored: "أرسل الـ Report بكرة") != .accept)
    }

    @Test("an Arabic word replaced by a Latin one that is not a word is still a swap, so the count is the net")
    func emptyResult() {
        #expect(EnglishRestoreGuard.check(original: "أسوي ميتنغ", restored: "") != .accept)
    }

    @Test("an Arabic prefix kept in front of the English word is allowed")
    func prefixKept() {
        #expect(EnglishRestoreGuard.check(original: "عشان الميتنغ بكرة", restored: "عشان الmeeting بكرة") == .accept)
    }
}
