import Foundation

/// Which server is on which port, and what it loaded.
///
/// Process-wide because the port is process-wide: two engines built a second apart
/// during a config reload would otherwise both think they owned 8711.
final class ServerRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: (process: Process, model: String)] = [:]

    func model(onPort port: Int) -> String? {
        lock.withLock {
            guard let entry = entries[port], entry.process.isRunning else { return nil }
            return entry.model
        }
    }

    func record(process: Process, model: String, port: Int) {
        lock.withLock { entries[port] = (process, model) }
    }

    func stop(port: Int) {
        let entry = lock.withLock { entries.removeValue(forKey: port) }
        entry?.process.terminate()
    }
}

/// Transcribes against a resident `whisper-server` instead of spawning the CLI.
///
/// The CLI reloads the model on every dictation. Measured on this machine with
/// the turbo model: 170 ms when the file is still in the page cache, 930 ms when
/// it is not, on top of the encode. A server loads it once and keeps it in GPU
/// memory, which also removes the cold-start spike that made the first dictation
/// after a quiet spell the slowest one of the day.
///
/// The server is Rawi's own child process: started on demand, health-checked, and
/// killed when the app quits. If it will not start, `TranscriptionEngineFactory`
/// falls back to the CLI rather than leaving the user with no dictation at all.
public final class WhisperServerEngine: TranscriptionEngine, @unchecked Sendable {
    private let binary: String
    private let model: String
    private let threads: Int
    private let port: Int
    private let detector: LanguageDetector?
    private let requestedLanguage: String
    private let log: any Logging

    private let lock = NSLock()
    private var server: Process?
    private var currentTask: URLSessionDataTask?
    private var session: URLSession { .shared }

    public init(binary: String = "whisper-server", model: String, threads: Int,
                language: String, port: Int = 8711,
                detector: LanguageDetector?, log: any Logging) {
        self.binary = binary
        self.model = model
        self.threads = threads
        self.requestedLanguage = language
        self.port = port
        self.detector = detector
        self.log = log
    }

    private var endpoint: URL { URL(string: "http://127.0.0.1:\(port)/inference")! }

    // MARK: - Lifecycle

    /// Starts the server if it is not already answering. Safe to call repeatedly;
    /// called at launch and again on the first key press, so the model is resident
    /// before anyone has finished speaking.
    /// The server this engine started, and the model it was started with. A
    ///健 health check alone was not enough: changing the model in Settings left the
    /// old server answering on the port with the old model loaded, so the setting
    /// appeared to do nothing.
    private static let running = ServerRegistry()

    /// Both residents: the model and, when auto is in play, the detector.
    @discardableResult
    public func warmAll() async -> Bool {
        let modelReady = await warm()
        let detectorReady = await detector?.warm() ?? true
        return modelReady && detectorReady
    }

    @discardableResult
    public func warm() async -> Bool {
        // Someone else's server, or ours with the wrong model, has to go first.
        if Self.running.model(onPort: port) != model {
            Self.running.stop(port: port)
            // Including one left behind by a previous run of the app: a crash, or a
            // kill that skipped the quit handler, leaves a server holding the port
            // with the old model still loaded. It answers, so every health check
            // says yes, and the model setting silently does nothing.
            Self.killStrays(onPort: port)
        } else if await isHealthy() {
            return true
        }
        lock.withLock {
            if let server, server.isRunning { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [binary, "-m", model, "--host", "127.0.0.1",
                                 "--port", String(port), "-t", String(threads)]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                self.server = process
                Self.running.record(process: process, model: model, port: port)
                log.info("""
                    Started whisper-server on port \(port) with \
                    \((model as NSString).lastPathComponent); the model stays resident
                    """)
            } catch {
                log.warn("Could not start whisper-server (\(error.localizedDescription))")
            }
        }
        // Loading a 574 MB model takes a moment; nothing else is waiting on it.
        for _ in 0..<40 {
            if await isHealthy() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// Kills any whisper-server holding our port that we did not start. Scoped
    /// twice over: only the configured port, and only processes that are actually
    /// whisper-server.
    static func killStrays(onPort port: Int) {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        lsof.arguments = ["lsof", "-tnP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = Pipe()
        guard (try? lsof.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()
        let pids = (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        for pid in pids where isWhisperServer(pid) { kill(pid, SIGTERM) }
    }

    private static func isWhisperServer(_ pid: Int32) -> Bool {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        ps.arguments = ["ps", "-o", "command=", "-p", String(pid)]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = Pipe()
        guard (try? ps.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").contains("whisper-server")
    }

    public func stop() {
        detector?.stop()
        Self.running.stop(port: port)
        lock.withLock { server = nil }
    }

    func isHealthy() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        request.timeoutInterval = 0.5
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode != nil
    }

    // MARK: - Transcription

    public func transcribe(wav: URL, prompt: String) async throws -> String {
        // An empty recording is not an error to report, it is nothing to do.
        guard AudioFile.hasAudio(at: wav) else { throw TranscriptionError.emptyResult }
        guard await warm() else { throw TranscriptionError.binaryNotFound(binary) }

        // One encode, not two. The detector costs about a tenth of a second and
        // lets the real model be told the answer instead of working it out.
        var language = requestedLanguage
        if requestedLanguage == "auto", let detector {
            if let detection = await detector.detect(wav: wav),
               detection.probability >= LanguageDetector.confidenceFloor {
                language = detection.language
                log.info(String(format: "Heard %@ (%.0f%% sure)",
                                detection.language, detection.probability * 100))
            } else {
                log.info("Language unclear; letting the model decide for itself")
            }
        }

        let body = try multipart(wav: wav, language: language, prompt: prompt)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(Self.boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let text: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    self.lock.withLock { self.currentTask = nil }
                    if let error = error as? URLError, error.code == .cancelled {
                        continuation.resume(throwing: TranscriptionError.cancelled); return
                    }
                    if let error {
                        continuation.resume(throwing: TranscriptionError.processFailed(
                            exitCode: -1, stderrTail: error.localizedDescription)); return
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status), let data else {
                        let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        continuation.resume(throwing: TranscriptionError.serverRejected(
                            status: status,
                            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)))
                        return
                    }
                    continuation.resume(returning: Self.parse(data))
                }
                lock.withLock { currentTask = task }
                task.resume()
            }
        } onCancel: {
            lock.withLock { currentTask }?.cancel()
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyResult }
        return trimmed
    }

    public func cancel() {
        lock.withLock { currentTask }?.cancel()
    }

    // MARK: - Wire format

    static let boundary = "rawi-boundary-7f3a2b"

    private func multipart(wav: URL, language: String, prompt: String) throws -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(Self.boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(Self.boundary)\r\n".utf8))
        let disposition = "Content-Disposition: form-data; name=\"file\"; "
                        + "filename=\"audio.wav\"\r\n"
        body.append(Data(disposition.utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: wav))
        body.append(Data("\r\n".utf8))
        field("language", language)
        field("response_format", "json")
        field("temperature", "0")
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append(Data("--\(Self.boundary)--\r\n".utf8))
        return body
    }

    static func parse(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            // The server returns one segment per line. The command-line path has
            // always joined them, and a sentence you spoke is one sentence.
            return Transcript.clean(text)
        }
        // Some builds answer in plain text; a transcript is still a transcript.
        return Transcript.clean(String(data: data, encoding: .utf8) ?? "")
    }
}
