import Foundation

/// Which language you just spoke, decided in about a tenth of a second.
///
/// whisper.cpp's `auto` costs an entire extra encoder pass: it encodes once to
/// detect, throws that away, and encodes again to transcribe. On the shipped
/// turbo model that is 1.4 seconds of every single dictation, and it is the
/// reason one key for two languages felt slow.
///
/// Detection does not need a good model, only a fast one. Measured on this
/// machine: `base` detects in 72 ms of encode and agrees with turbo on English,
/// on Arabic, and on a sentence that switches between them mid-clause.
///
/// It runs against its own resident server rather than the command line. The
/// encode was never the cost: spawning a process, initialising Metal and loading
/// the model came to 700-1500 ms under load, which was more than the
/// transcription it was supposed to make cheaper. Resident, the same answer takes
/// about 400 ms.
public final class LanguageDetector: @unchecked Sendable {
    public struct Detection: Sendable, Equatable {
        public let language: String
        public let probability: Double
    }

    private let model: String
    private let threads: Int
    private let port: Int
    private let serverBinary: String
    private let log: any Logging
    private let lock = NSLock()
    private var server: Process?

    /// Below this, the detector is guessing and the caller should pay for a full
    /// `auto` pass rather than pin the wrong language. Being slow is recoverable;
    /// transcribing Arabic as English is not.
    public static let confidenceFloor = 0.6

    public init(serverBinary: String = "whisper-server", model: String,
                threads: Int = 4, port: Int = 8712, log: any Logging = SilentLog()) {
        self.serverBinary = serverBinary
        self.model = model
        self.threads = threads
        self.port = port
        self.log = log
    }

    /// Loads the detector's model so the first dictation does not pay for it.
    @discardableResult
    public func warm() async -> Bool {
        if await isHealthy() { return true }
        WhisperServerEngine.killStrays(onPort: port)
        // Resolved, not left to `env`: see `WhisperServerEngine.warm()`.
        guard let executable = ToolBinary.resolve(serverBinary) else {
            log.warn("\(serverBinary) is not on PATH or in Homebrew's bin; no language detector")
            return false
        }
        lock.withLock {
            guard server == nil || server?.isRunning == false else { return }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["-m", model, "--host", "127.0.0.1",
                                 "--port", String(port), "-t", String(threads)]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            if (try? process.run()) != nil {
                server = process
                log.info("Language detector resident on port \(port)")
            }
        }
        for _ in 0..<20 {
            if await isHealthy() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    public func stop() {
        lock.withLock {
            server?.terminate()
            server = nil
        }
    }

    private func isHealthy() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        request.timeoutInterval = 0.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse) != nil
    }

    public func detect(wav: URL) async -> Detection? {
        guard FileManager.default.fileExists(atPath: model), await warm() else { return nil }
        guard let body = try? multipart(wav: wav) else { return nil }
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("multipart/form-data; boundary=\(WhisperServerEngine.boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return Self.parse(json: data)
    }

    private func multipart(wav: URL) throws -> Data {
        var body = Data()
        let boundary = WhisperServerEngine.boundary
        body.append(Data("--\(boundary)\r\n".utf8))
        let disposition = "Content-Disposition: form-data; name=\"file\"; "
                        + "filename=\"audio.wav\"\r\n"
        body.append(Data(disposition.utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: wav))
        body.append(Data("\r\n".utf8))
        // Ask only for the language. The detector used to request a full
        // transcript from the base model and read the language off the top of
        // it, which is a whole decode to answer a question the encoder has
        // already answered: 380ms against 260ms on the same clip. `verbose_json`
        // is what carries `detected_language` — the plainer formats return an
        // empty body with no language in it at all.
        for (name, value) in [("detect_language", "true"),
                              ("response_format", "verbose_json")] {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// What `detect_language=true` with `verbose_json` answers.
    ///
    /// whisper-server names the language rather than coding it ("arabic", not
    /// "ar"); whisper accepts either, so the name goes straight through.
    ///
    /// The probability is the model's own. It used to be hard-coded to 1, which
    /// quietly retired `confidenceFloor`: a detection could never be too unsure
    /// to use, so a wrong one was never handed back to the big model to settle.
    static func parse(json data: Data) -> Detection? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let language = (json["detected_language"] ?? json["language"]) as? String,
              !language.isEmpty, language != "auto" else { return nil }
        let probability = json["detected_language_probability"] as? Double ?? 1
        return Detection(language: language, probability: probability)
    }

    /// `whisper_full_with_state: auto-detected language: ar (p = 0.995071)`
    static func parse(_ output: String) -> Detection? {
        guard let range = output.range(of: "auto-detected language: ") else { return nil }
        let tail = output[range.upperBound...]
        let code = tail.prefix { $0.isLetter }
        guard !code.isEmpty else { return nil }
        var probability = 1.0
        if let open = tail.range(of: "p = "),
           let value = Double(tail[open.upperBound...].prefix { $0.isNumber || $0 == "." }) {
            probability = value
        }
        return Detection(language: String(code), probability: probability)
    }
}
