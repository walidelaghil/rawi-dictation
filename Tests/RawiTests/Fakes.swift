import Foundation
@testable import RawiCore

final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var level = 0.0
    var cancelled = false
    var startedURLs: [URL] = []
    var stubDuration: Duration = .seconds(3)
    var startError: (any Error)?
    /// Overrides what `stop()` returns, for tests about the audio itself.
    var stopResult: RecordingResult?

    func start(to url: URL) throws {
        if let startError { throw startError }
        isRecording = true
        startedURLs.append(url)
        // Write something, because a recorder does. The controller now refuses to
        // send an empty file down the pipeline, and a fake that leaves no file at
        // all is not a recorder that captured nothing — it is one that never ran.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(contentsOf: [36, 0, 0, 0])
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        wav.append(contentsOf: [16, 0, 0, 0, 1, 0, 1, 0])
        wav.append(contentsOf: [0x80, 0x3E, 0, 0, 0, 0x7D, 0, 0, 2, 0, 16, 0])
        wav.append(contentsOf: Array("data".utf8))
        wav.append(contentsOf: [0, 0, 0, 0])
        wav.append(Data(repeating: 0, count: 32_000))          // a second of silence
        try? wav.write(to: url)
    }
    func stop() throws -> RecordingResult {
        isRecording = false
        if let stopResult { return stopResult }
        return RecordingResult(url: startedURLs.last!, duration: stubDuration)
    }
    func cancel() { isRecording = false; cancelled = true }
}

final class FakeEngine: TranscriptionEngine, @unchecked Sendable {
    var result: Result<String, any Error> = .success("um raw transcript")
    var cancelCount = 0
    var callCount = 0
    var lastPrompt: String = ""
    func transcribe(wav: URL, prompt: String) async throws -> String {
        callCount += 1
        lastPrompt = prompt
        return try result.get()
    }
    func cancel() { cancelCount += 1 }
}

final class FakeCleanup: CleanupProvider, @unchecked Sendable {
    var result: Result<String, any Error> = .success("Cleaned transcript.")
    var received: [String] = []
    var cancelCount = 0
    var lastInstruction: String = ""
    func clean(_ t: String, instruction: String) async throws -> String {
        received.append(t)
        lastInstruction = instruction
        return try result.get()
    }
    func cancel() { cancelCount += 1 }
}

final class FakeInserter: TextInserting, @unchecked Sendable {
    var inserted: [String] = []
    var staged: [String] = []
    var replaced: [(from: String, to: String)] = []
    var restoreFlags: [Bool] = []
    var succeed = true
    /// Whether the staged text is still what is on the clipboard.
    var stagedSurvives = true

    func insert(_ text: String, restoringClipboard: Bool) -> Bool {
        inserted.append(text)
        restoreFlags.append(restoringClipboard)
        return succeed
    }

    @discardableResult
    func stage(_ text: String) -> Bool {
        staged.append(text)
        return true
    }

    @discardableResult
    func replace(staged from: String, with text: String) -> Bool {
        guard stagedSurvives else { return false }
        replaced.append((from, text))
        inserted.append(text)
        return succeed
    }

    /// Clipboard-only deliveries, which never count as inserted.
    var upgraded: [(from: String, to: String)] = []
    @discardableResult
    func upgrade(staged from: String, with text: String) -> Bool {
        guard stagedSurvives else { return false }
        upgraded.append((from, text))
        return true
    }
}

final class FakeFocus: FocusProbing, @unchecked Sendable {
    var result: FocusedInput = .editable
    var prepared = 0
    func prepare() { prepared += 1 }
    func probe() -> FocusedInput { result }
    var lastSeen: String { "fake: \(result.rawValue)" }
}

final class FakeLog: Logging, @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    func log(_ level: LogLevel, _ message: String) {
        lock.withLock { _lines.append("\(level): \(message)") }
    }
}
