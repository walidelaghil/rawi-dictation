import Foundation
import Testing
@testable import RawiCore

/// Counts what it was asked to transcribe, and answers with the chunk's length.
private final class ChunkEngine: TranscriptionEngine, @unchecked Sendable {
    let lock = NSLock()
    var seconds: [Double] = []
    var failAfter: Int?

    func transcribe(wav: URL, prompt: String) async throws -> String {
        let bytes = (try Data(contentsOf: wav)).count - 44
        let s = Double(bytes / 2) / 16_000
        let n = lock.withLock { seconds.append(s); return seconds.count }
        if let failAfter, n > failAfter {
            throw TranscriptionError.processFailed(exitCode: 1, stderrTail: "boom")
        }
        return "chunk\(n)"
    }
    func cancel() {}
}

/// Speech-like noise with a 600 ms pause at each of `pauses` (in seconds).
private func speech(seconds: Double, pauses: [Double]) -> [Int16] {
    let n = Int(seconds * 16_000)
    var out = [Int16](repeating: 0, count: n)
    var g = SystemRandomNumberGenerator()
    for i in 0..<n {
        let t = Double(i) / 16_000
        let paused = pauses.contains { t >= $0 && t < $0 + 0.6 }
        out[i] = paused ? 0 : Int16.random(in: -6000...6000, using: &g)
    }
    return out
}

@Suite struct RollingTranscriberTests {
    @Test func cutsInThePauseNotMidWord() throws {
        let audio = speech(seconds: 26, pauses: [21.0])
        let cut = try #require(RollingTranscriber.cutPoint(in: audio))
        let at = Double(cut) / 16_000
        #expect(at > 21.0 && at < 21.6, "cut at \(at)s")
    }

    @Test func neverCutsThroughSpeechWhileThereIsTimeToWait() {
        // 30 s without a breath: wait for one rather than split a word.
        #expect(RollingTranscriber.cutPoint(in: speech(seconds: 30, pauses: [])) == nil)
    }

    @Test func cutsAnywayOnceAPauseIsOverdue() {
        #expect(RollingTranscriber.cutPoint(in: speech(seconds: 46, pauses: [])) != nil)
    }

    @Test func noCutBeforeFifteenSeconds() {
        #expect(RollingTranscriber.cutPoint(in: speech(seconds: 14, pauses: [5])) == nil)
    }

    @Test func shortDictationIsLeftToTheOrdinaryPath() async throws {
        let engine = ChunkEngine()
        let audio = speech(seconds: 8, pauses: [])
        let roller = RollingTranscriber(engine: engine, prompt: "", log: SilentLog(),
                                        read: { Array(audio[min($0, audio.count)...]) })
        roller.start()
        try await Task.sleep(for: .milliseconds(600))
        #expect(try await roller.finish() == nil)
        #expect(engine.seconds.isEmpty)
    }

    @Test func longDictationLeavesOnlyTheTailForRelease() async throws {
        let engine = ChunkEngine()
        let audio = speech(seconds: 70, pauses: [18, 37, 55])
        // Arrives as speech does, only faster: 70 seconds over 3.5.
        let began = ContinuousClock.now
        let roller = RollingTranscriber(engine: engine, prompt: "", log: SilentLog(),
                                        read: { offset in
            let elapsed = Double(began.duration(to: .now).milliseconds) / 1000
            let available = min(audio.count, Int(elapsed * 20 * 16_000))
            return offset < available ? Array(audio[offset..<available]) : []
        })
        roller.start()
        try await Task.sleep(for: .seconds(5))
        let text = try #require(try await roller.finish())
        #expect(engine.seconds.count >= 3)
        // Nothing lost, nothing transcribed twice.
        #expect(abs(engine.seconds.reduce(0, +) - 70) < 0.05)
        // Every chunk ended in a pause, and the tail is short.
        #expect(engine.seconds.last! < 20)
        #expect(text.hasPrefix("chunk1 chunk2"))
    }

    @Test func failedChunkFallsBackToTheWholeFile() async throws {
        let engine = ChunkEngine()
        engine.failAfter = 0
        let audio = speech(seconds: 40, pauses: [18])
        let roller = RollingTranscriber(engine: engine, prompt: "", log: SilentLog(),
                                        read: { Array(audio[min($0, audio.count)...]) })
        roller.start()
        try await Task.sleep(for: .seconds(1))
        #expect(try await roller.finish() == nil)
    }

    @Test func silentChunkIsNotSentToWhisper() async throws {
        let engine = ChunkEngine()
        var audio = [Int16](repeating: 0, count: 22 * 16_000)   // 22 s of nothing
        audio += speech(seconds: 3, pauses: [])
        let snapshot = audio
        let roller = RollingTranscriber(engine: engine, prompt: "", log: SilentLog(),
                                        read: { Array(snapshot[min($0, snapshot.count)...]) })
        roller.start()
        try await Task.sleep(for: .seconds(1))
        let text = try await roller.finish()
        #expect(engine.seconds.count == 1)          // only the spoken tail
        #expect(text == "chunk1")
    }
}
