import Foundation

/// Polishes English on the fast model and anything with Arabic in it on the model
/// that keeps Arabic.
///
/// Measured with the shipped polish prompt: qwen2.5:1.5b passed every English
/// case — corrections, run-ons, the sentence-order case, a spoken list, prompt
/// injection — at about half qwen2.5:3b's latency, because it types its output
/// twice as fast. It also translates Arabic into English. So the choice is not
/// by *dominant* script, the way cleanup routes, but by whether a single Arabic
/// letter is present: code-switched speech is the product's bet, and one Arabic
/// word inside an English sentence is exactly what the small model would quietly
/// translate away.
public final class ScriptRoutedProvider: CleanupProvider, @unchecked Sendable {
    private let latin: any CleanupProvider
    private let arabic: any CleanupProvider

    public init(latin: any CleanupProvider, arabic: any CleanupProvider) {
        self.latin = latin
        self.arabic = arabic
    }

    static func needsArabicModel(_ text: String) -> Bool {
        ScriptDetector.arabicRatio(text) > 0
    }

    public func clean(_ transcript: String, instruction: String) async throws -> String {
        let provider = Self.needsArabicModel(transcript) ? arabic : latin
        return try await provider.clean(transcript, instruction: instruction)
    }

    /// Always the bigger model, whatever the script.
    ///
    /// Measured on the transcript that exposed this: asked to clean a dictation
    /// that enumerates something, qwen2.5:1.5b moved the ordinals to the ends of
    /// their clauses and dropped a phrase, so the list that came out was a list of
    /// the wrong things. qwen2.5:3b kept "first", "second" and "third" exactly
    /// where they were spoken. The small model is chosen for being twice as fast,
    /// and on a dictation with a shape to lose that is the wrong trade.
    public func cleanKeepingShape(_ transcript: String,
                                  instruction: String) async throws -> String {
        try await arabic.clean(transcript, instruction: instruction)
    }

    /// Both, because which one this dictation needs is not known until it is heard.
    public func warm() async {
        async let english: Void = latin.warm()
        async let arabicReady: Void = arabic.warm()
        _ = await (english, arabicReady)
    }

    public func cancel() {
        latin.cancel()
        arabic.cancel()
    }
}
