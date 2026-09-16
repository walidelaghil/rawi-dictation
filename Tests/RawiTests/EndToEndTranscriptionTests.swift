import Testing
import Foundation
@testable import RawiCore

/// Proves that audio written by our own `WAVWriter` is accepted by the real
/// `whisper-cli`. This is the one integration worth paying for: a malformed WAV
/// header does not make whisper.cpp fail, it makes it emit silent garbage, so
/// nothing but a real round trip catches it.
///
/// Skipped automatically when the model or binary is absent, so `swift test`
/// stays green on a machine that has not downloaded a model.
@Suite("End-to-end transcription", .serialized) struct EndToEndTranscriptionTests {
    static var modelPath: String { Config.expand(Config.defaultWhisperCpp.model) }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: modelPath)
            && WhisperCppEngine.resolveBinary("whisper-cli") != nil
    }

    @Test("audio written by WAVWriter round-trips through whisper-cli",
          .enabled(if: EndToEndTranscriptionTests.isAvailable),
          .timeLimit(.minutes(2)))
    func roundTrip() async throws {
        let spoken = "The quick brown fox jumps over the lazy dog"

        // 1. Synthesize speech with `say` into a reference WAV.
        let reference = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-e2e-say-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: reference) }
        try runSay(text: spoken, to: reference)

        // 2. Re-encode its samples through our own writer.
        let samples = try Self.pcmSamples(of: reference)
        #expect(samples.count > 16_000)          // at least a second of audio

        let ours = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-e2e-ours-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: ours) }

        let writer = try WAVWriter(url: ours)
        // Append in chunks, the way the live audio tap does.
        for chunk in samples.chunked(into: 4096) { try writer.append(chunk) }
        try writer.finalize()

        // 3. Transcribe our file and check the words came through.
        let engine = WhisperCppEngine(binary: "whisper-cli", model: Self.modelPath,
                                      language: "en", threads: 8)
        let text = try await engine.transcribe(wav: ours).lowercased()

        for word in ["quick", "brown", "fox", "lazy", "dog"] {
            #expect(text.contains(word), "expected “\(word)” in transcript: \(text)")
        }
    }

    private func runSay(text: String, to url: URL) throws {
        try SpokenAudio.speak(text, to: url)
    }

    /// Finds the `data` chunk rather than assuming a 44-byte header, because
    /// `say` writes extra chunks.
    static func pcmSamples(of url: URL) throws -> [Int16] {
        let data = try Data(contentsOf: url)
        var offset = 12                                   // past "RIFF....WAVE"
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset+4], as: UTF8.self)
            let size = Int(UInt32(data[offset+4]) | UInt32(data[offset+5]) << 8
                           | UInt32(data[offset+6]) << 16 | UInt32(data[offset+7]) << 24)
            let body = offset + 8
            if id == "data" {
                let end = min(body + size, data.count)
                let bytes = Array(data[body..<end])
                return stride(from: 0, to: bytes.count - 1, by: 2).map {
                    Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)
                }
            }
            offset = body + size + (size % 2)             // chunks are word-aligned
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
