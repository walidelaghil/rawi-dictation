import Foundation

/// Synthesised speech, for the tests that need real audio rather than a fixture.
enum SpokenAudio {
    struct Stuck: Error, CustomStringConvertible {
        let seconds: Double
        var description: String {
            "/usr/bin/say did not finish within \(Int(seconds))s and was killed"
        }
    }

    /// `say` writing to a file normally takes under a second, but it talks to a
    /// system service that can wedge — two processes asking at once was enough,
    /// and it then sat at 0% CPU indefinitely. A test's `.timeLimit` does not
    /// rescue that: the trait records an issue when the clock runs out, while the
    /// thread stays blocked in `waitUntilExit()`, so one stuck call held a whole
    /// suite for twenty-one minutes. The watchdog is what actually ends it.
    static func speak(_ text: String, voice: String? = nil,
                      to url: URL, timeout: Double = 60) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var arguments = ["-o", url.path, "--data-format=LEI16@16000"]
        if let voice { arguments += ["-v", voice] }
        arguments.append(text)
        process.arguments = arguments
        try process.run()

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { throw Stuck(seconds: timeout) }
    }

    /// The same, into a temporary file named after the caller's suite.
    static func wav(_ text: String, voice: String? = nil, prefix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).wav")
        try speak(text, voice: voice, to: url)
        return url
    }
}
