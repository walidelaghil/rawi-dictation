import AVFoundation
import Foundation

/// Questions about a recording that can be answered without decoding it.
public enum AudioFile {
    /// A WAV header is 44 bytes. A file that size is a recording that captured
    /// nothing: a key tapped and released before the microphone delivered a single
    /// buffer.
    ///
    /// It matters because an empty file is not harmless downstream. The command
    /// line returned an empty transcript, which looked like silence; the
    /// transcription server refuses it outright with an HTTP 400, which reached the
    /// user as an error about a program that was not involved.
    public static let headerBytes = 44

    public static func hasAudio(at url: URL, minimumSamples: Int = 1600) -> Bool {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int else { return false }
        // 1600 samples of 16-bit mono is a tenth of a second: shorter than any word.
        return size >= headerBytes + minimumSamples * 2
    }

    /// Length of a recording made by `AudioRecorder`: 16 kHz, 16-bit, mono.
    public static func seconds(bytes: Int) -> Double {
        Double(max(0, bytes - headerBytes)) / 32_000
    }

    public static func seconds(at url: URL) -> Double {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return seconds(bytes: size)
    }
}
