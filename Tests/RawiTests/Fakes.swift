import Foundation
@testable import RawiCore

final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var level = 0.0
    var cancelled = false
    var startedURLs: [URL] = []
    var stubDuration: Duration = .seconds(3)
    var startError: (any Error)?

    func start(to url: URL) throws {
        if let startError { throw startError }
        isRecording = true
        startedURLs.append(url)
    }
    func stop() throws -> RecordingResult {
        isRecording = false
        return RecordingResult(url: startedURLs.last!, duration: stubDuration)
    }
    func cancel() { isRecording = false; cancelled = true }
}

final class FakeEngine: TranscriptionEngine, @unchecked Sendable {
    var result: Result<String, any Error> = .success("raw transcript")
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
}

final class FakeLog: Logging, @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    func log(_ level: LogLevel, _ message: String) {
        lock.withLock { _lines.append("\(level): \(message)") }
    }
}
