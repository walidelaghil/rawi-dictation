import AppKit

/// Whether a word is ordinary English, according to the dictionary macOS ships.
///
/// The dictionary's own fence used to be a list of about 130 common words, which
/// is how "billing" and "actually" got through it: neither was on the list.
/// macOS already knows every ordinary English word — and, usefully, keeps the
/// words *you* have taught it separately, so "Kandji", learned from your own
/// typing, is not counted as ordinary.
public enum SpellCheck {
    /// How long macOS's spell service gets to answer before the answer is assumed.
    ///
    /// It normally answers in well under a millisecond, and then one day it does
    /// not: caught mid-test sitting at 0% CPU inside `checkSpelling`, with
    /// `AppleSpell` alive and silent. The learner runs in the background and used
    /// to reach this through `DispatchQueue.main.sync`, so a service that stops
    /// answering takes the main thread with it — every window, the pill, the
    /// hotkey. Learning a word is not worth that.
    static let patience = 2.0

    public static func isOrdinaryEnglish(_ word: String) -> Bool {
        // NSSpellChecker belongs to the main thread.
        if Thread.isMainThread { return check(word) }

        let answer = Answer()
        DispatchQueue.main.async { answer.settle(check(word)) }
        // True is the assumption that changes nothing: the word is treated as
        // ordinary English, so it is simply not learned this time.
        return answer.wait(patience) ?? true
    }

    private static func check(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: "en",
                                         wrap: false, inSpellDocumentWithTag: 0,
                                         wordCount: nil)
        return miss.location == NSNotFound && !checker.hasLearnedWord(word)
    }

    private final class Answer: @unchecked Sendable {
        private let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: Bool?

        func settle(_ new: Bool) {
            lock.withLock { value = new }
            ready.signal()
        }

        func wait(_ seconds: Double) -> Bool? {
            guard ready.wait(timeout: .now() + seconds) == .success else { return nil }
            return lock.withLock { value }
        }
    }
}
