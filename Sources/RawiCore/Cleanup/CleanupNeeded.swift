import Foundation

/// Whether a transcript is worth sending to the model at all.
///
/// Cleanup costs one to three seconds of GPU on this machine, on every dictation,
/// including "Thank you." — and it competes with transcription for the same GPU,
/// so the cost lands on the *next* dictation too. Most of what whisper returns is
/// already clean: it punctuates, it capitalises, and the filler it leaves behind
/// is the filler you actually said.
///
/// The test is deliberately conservative in one direction. A false "needed" wastes
/// a second; a false "not needed" ships text with "um" in it, which is the thing
/// the feature exists to remove.
public enum CleanupNeeded {
    /// Fillers worth a round trip. Short ones like "um" and "uh" need word
    /// boundaries, or "um" fires inside "number".
    static let fillers = ["um", "uh", "erm", "hmm", "like", "you know", "i mean",
                          "sort of", "kind of", "basically", "actually", "literally",
                          "so yeah", "right", "okay so", "well"]

    public static func check(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let lower = trimmed.lowercased()
        for filler in fillers {
            if filler.contains(" ") {
                if lower.contains(filler) { return true }
            } else if words.contains(where: { word in
                word.lowercased().trimmingCharacters(
                    in: CharacterSet.alphanumerics.inverted) == filler
            }) {
                return true
            }
        }

        // Filler is checked before length: "um yes please" is three words and one
        // of them is the whole reason this stage exists.
        //
        // Below four words there is no sentence structure to fix and no room for a
        // false start to hide.
        if words.count <= 3 { return false }

        // Unpunctuated or uncapitalised output is whisper having a bad time, and
        // the model fixes exactly that.
        guard let first = trimmed.first, let last = trimmed.last else { return false }
        if first.isLowercase && first.isLetter { return true }
        if !".!?۔؟".contains(last) { return true }

        // A very long single sentence is usually missing its boundaries.
        if words.count > 60, !trimmed.dropLast().contains(where: { ".!?۔؟".contains($0) }) {
            return true
        }
        return false
    }
}
