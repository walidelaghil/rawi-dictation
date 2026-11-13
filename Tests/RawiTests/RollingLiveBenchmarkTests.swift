import Foundation
import Testing
@testable import RawiCore

/// How long you wait after letting go, with and without rolling, against the
/// real whisper-server. Point it at a long recording (a minute or more) and run:
///
///     RAWI_LIVE_LONG_WAV=/path/to.wav swift test --filter RollingLiveBenchmark
///
/// Talks to the port directly rather than through `WhisperServerEngine`, whose
/// `warm()` would replace the app's own running server.
@Suite("Rolling transcription, live", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["RAWI_LIVE_LONG_WAV"] != nil))
struct RollingLiveBenchmarkTests {
    static let wav = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["RAWI_LIVE_LONG_WAV"] ?? "/dev/null")
    static let port = Int(ProcessInfo.processInfo.environment["RAWI_LIVE_PORT"] ?? "") ?? 8711
    /// How much faster than real time the recording is "spoken".
    static let speed = Double(ProcessInfo.processInfo.environment["RAWI_LIVE_SPEED"] ?? "") ?? 4

    final class PortEngine: TranscriptionEngine, @unchecked Sendable {
        let port: Int
        init(port: Int) { self.port = port }
        func transcribe(wav: URL, prompt: String) async throws -> String {
            let boundary = WhisperServerEngine.boundary
            var body = Data()
            func field(_ n: String, _ v: String) {
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".utf8))
            }
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
            body.append(try Data(contentsOf: wav))
            body.append(Data("\r\n".utf8))
            field("language", "en"); field("response_format", "json"); field("temperature", "0")
            body.append(Data("--\(boundary)--\r\n".utf8))
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 300
            request.setValue("multipart/form-data; boundary=\(boundary)",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (data, _) = try await URLSession.shared.data(for: request)
            return WhisperServerEngine.parse(data)
        }
        func cancel() {}
    }

    static func samples() throws -> [Int16] {
        let data = try Data(contentsOf: wav).dropFirst(44)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }

    @Test func releaseLatency() async throws {
        let engine = PortEngine(port: Self.port)
        let audio = try Self.samples()
        let seconds = Double(audio.count) / 16_000

        // Before: everything waits for the key to come up.
        var t = ContinuousClock.now
        let whole = try await engine.transcribe(wav: Self.wav, prompt: "")
        let before = t.duration(to: .now).milliseconds

        // After: audio arrives as it is spoken, and only the tail is left on release.
        let began = ContinuousClock.now
        let speed = Self.speed
        let roller = RollingTranscriber(engine: engine, prompt: "", log: SilentLog(),
                                        read: { offset in
            let elapsed = Double(began.duration(to: .now).milliseconds) / 1000
            let available = min(audio.count, Int(elapsed * speed * 16_000))
            return offset < available ? Array(audio[offset..<available]) : []
        })
        roller.start()
        try await Task.sleep(for: .milliseconds(Int(seconds / speed * 1000)))
        t = ContinuousClock.now
        let rolled = try #require(try await roller.finish())
        let after = t.duration(to: .now).milliseconds

        let wordsBefore = whole.split(separator: " ").count
        let wordsAfter = rolled.split(separator: " ").count
        print(String(format: "BENCH %.1fs audio | whole-file after release: %dms (%d words) | rolling after release: %dms (%d words)",
                     seconds, before, wordsBefore, after, wordsAfter))
        try? whole.write(toFile: NSTemporaryDirectory() + "rawi-bench-whole.txt", atomically: true, encoding: .utf8)
        try? rolled.write(toFile: NSTemporaryDirectory() + "rawi-bench-rolled.txt", atomically: true, encoding: .utf8)
        #expect(abs(wordsBefore - wordsAfter) <= max(4, wordsBefore / 20))
    }
}
