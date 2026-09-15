import AppKit

/// Whether a word is ordinary English, according to the dictionary macOS ships.
///
/// The dictionary's own fence used to be a list of about 130 common words, which
/// is how "billing" and "actually" got through it: neither was on the list.
/// macOS already knows every ordinary English word — and, usefully, keeps the
/// words *you* have taught it separately, so "Kandji", learned from your own
/// typing, is not counted as ordinary.
public enum SpellCheck {
    public static func isOrdinaryEnglish(_ word: String) -> Bool {
        let check = {
            let checker = NSSpellChecker.shared
            let miss = checker.checkSpelling(of: word, startingAt: 0, language: "en",
                                             wrap: false, inSpellDocumentWithTag: 0,
                                             wordCount: nil)
            return miss.location == NSNotFound && !checker.hasLearnedWord(word)
        }
        // NSSpellChecker belongs to the main thread.
        return Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
    }
}
