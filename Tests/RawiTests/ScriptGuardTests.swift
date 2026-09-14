import Testing
@testable import RawiCore

@Suite("Refusing a rewrite in the wrong language") struct ScriptGuardTests {
    let english = "It is remarkably fast and I need the quality to be high."
    let arabic = "إنه سريع للغاية وأنا أحتاج إلى أن تكون الجودة عالية."

    let toArabic = "Translate into natural Modern Standard Arabic. Leave technical terms "
                 + "and product names in Latin script."

    @Test("a translation into the language you asked for is accepted") func translation() {
        #expect(ScriptGuard.check(input: english, output: arabic, instruction: toArabic)
                == .accept)
    }

    @Test("a rewrite that stays in the same language is accepted") func sameLanguage() {
        #expect(ScriptGuard.check(input: english, output: "It is fast. The quality matters.")
                == .accept)
    }

    @Test("a third script nobody asked for is refused") func thirdScript() {
        // What actually happened: asked for Arabic, qwen answered in Chinese.
        let chinese = "实实在在它其实非常快，我需要确保质量是很高的。"
        #expect(ScriptGuard.check(input: english, output: chinese, instruction: toArabic)
                != .accept)
    }

    @Test("half a translation is refused") func halfDone() {
        // Also what happened: one sentence in Arabic, the rest left in English with
        // a line of Chinese at the end.
        let mixed = "هذا بالفعل سرعة مدهشة، وأنا أحب ذلك. somehow, the quality keeps "
                  + "adding things in different lines; I need to 确保它是高质量的。"
        #expect(ScriptGuard.check(input: english, output: mixed, instruction: toArabic)
                != .accept)
    }

    @Test("technical terms left in Latin are fine") func technicalTerms() {
        // The built-in transform says to leave product names in Latin script, and a
        // few of them must not look like a failed translation.
        let mostlyArabic = "سنرسل التقرير إلى Slack قبل يوم الاثنين باستخدام Airtable."
        #expect(ScriptGuard.check(input: english, output: mostlyArabic, instruction: toArabic)
                == .accept)
    }

    @Test("a script already in the input is never a surprise") func inputHadIt() {
        let mixedInput = "Send the 报告 to the team."
        #expect(ScriptGuard.check(input: mixedInput, output: "Send the 报告 today.") == .accept)
    }

    @Test("an empty rewrite is refused") func empty() {
        #expect(ScriptGuard.check(input: english, output: "   ") != .accept)
    }

    @Test("a rewrite with no language named must stay where it started") func noTarget() {
        // "Make it shorter" is not permission to answer in another language.
        #expect(ScriptGuard.check(input: english, output: "It is fast.",
                                  instruction: "Cut this to its essential message.") == .accept)
        #expect(ScriptGuard.check(input: english, output: "它很快。",
                                  instruction: "Cut this to its essential message.") != .accept)
    }
}
