import Testing
import Foundation
@testable import RawiCore

@MainActor
@Suite("A recording with nothing in it") struct EmptyRecordingTests {
    /// A 44-byte WAV: a header and no samples. This is what a key tapped too
    /// briefly produces, and it reached the transcription server, which refused it
    /// with an HTTP 400 that the pill reported as "whisper-cli exited 400".
    func emptyWav() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-empty-\(UUID().uuidString).wav")
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(contentsOf: [36, 0, 0, 0])
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        header.append(contentsOf: [16, 0, 0, 0, 1, 0, 1, 0])
        header.append(contentsOf: [0x80, 0x3E, 0, 0, 0, 0x7D, 0, 0, 2, 0, 16, 0])
        header.append(contentsOf: Array("data".utf8))
        header.append(contentsOf: [0, 0, 0, 0])
        try header.write(to: url)
        return url
    }

    @Test("is recognised before anything is asked to transcribe it") func recognised() throws {
        let url = try emptyWav()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(AudioFile.hasAudio(at: url) == false)
    }

    @Test("a real recording is not mistaken for an empty one") func real() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-real-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = try Data(contentsOf: try emptyWav())
        data.append(Data(repeating: 0, count: 16_000))      // half a second of samples
        try data.write(to: url)
        #expect(AudioFile.hasAudio(at: url))
    }

    @Test("a missing file is not audio either") func missing() {
        #expect(AudioFile.hasAudio(at: URL(fileURLWithPath: "/tmp/does-not-exist.wav")) == false)
    }

    @Test("an empty recording ends quietly, not as a failure") func quiet() async throws {
        // It used to reach the server, come back 400, and land in History as a
        // failed dictation with a retry button for audio that contains nothing.
        let url = try emptyWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        r.stopResult = RecordingResult(url: url, duration: .milliseconds(40), peakLevel: 0)
        var recorded: [HistoryEntry] = []
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: l)
        ctl.onRecord = { recorded.append($0) }
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(ctl.state == .idle)
        #expect(recorded.isEmpty)
        #expect(e.callCount == 0)           // never asked
        #expect(i.inserted.isEmpty)
    }
}

@Suite("What the server's refusals say") struct ServerErrorTests {
    @Test("a 400 says what went wrong, not which binary was blamed") func fourHundred() {
        // It read "whisper-cli exited 400: whisper-server", naming a program that
        // was not involved and a number that is an HTTP status.
        let message = TranscriptionError.serverRejected(status: 400, detail: "Invalid request")
            .errorDescription
        #expect(message == "The recording could not be read")
        #expect(message?.contains("whisper-cli") == false)
        #expect(message?.contains("400") == false)
    }

    @Test("other statuses keep their detail, because they are rarer and stranger")
    func other() {
        let message = TranscriptionError.serverRejected(status: 503, detail: "loading")
            .errorDescription
        #expect(message?.contains("503") == true)
        #expect(message?.contains("loading") == true)
    }
}
