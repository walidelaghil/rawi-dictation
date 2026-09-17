import Foundation

/// Local transcription by spawning Homebrew's `whisper-cli`.
///
/// Verified invocation:
///     whisper-cli -m MODEL -f WAV -nt -np -sns -l LANG -t N
///
/// Results arrive on **stdout**; ggml/Metal diagnostics arrive on **stderr**. The two
/// are read into separate pipes and never merged — merging corrupts the transcript.
/// Both pipes are drained concurrently, because whisper-cli is chatty enough on stderr
/// to fill the 64 KB pipe buffer and deadlock a single-pipe reader.
/// Thread-safe collector for the two pipe-draining queues.
private final class PipeSink: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func store(_ d: Data, isStdout: Bool) {
        lock.withLock { if isStdout { out = d } else { err = d } }
    }
    var contents: (Data, Data) { lock.withLock { (out, err) } }
}

public final class WhisperCppEngine: TranscriptionEngine, @unchecked Sendable {
    private let binary: String
    private let model: String
    private let language: String
    /// Set from the pill when detection got it wrong. Behind the lock because the
    /// click and the transcription are on different threads.
    private var chosenLanguage: DictationLanguage = .auto
    private let threads: Int

    private let lock = NSLock()
    private var process: Process?
    private var wasCancelled = false

    private let detector: LanguageDetector?

    public init(binary: String, model: String, language: String, threads: Int,
                detector: LanguageDetector? = nil) {
        self.detector = detector
        self.binary = binary
        self.model = model
        self.language = language
        self.threads = threads
    }

    public func transcribe(wav: URL, prompt: String = "") async throws -> String {
        // Ask the cheap model which language this is, so the expensive one is told
        // rather than made to work it out with a whole extra encoder pass.
        // What you chose beats what the configuration says, and skips the
        // detector entirely — there is nothing to detect once you have said so.
        var language = lock.withLock { chosenLanguage.whisperCode } ?? self.language
        if language == "auto", let detector,
           let detection = await detector.detect(wav: wav),
           detection.probability >= LanguageDetector.confidenceFloor {
            language = detection.language
        }
        guard let executable = Self.resolveBinary(binary) else {
            throw TranscriptionError.binaryNotFound(binary)
        }
        let modelPath = Config.expand(model)
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionError.modelNotFound(modelPath)
        }

        lock.withLock { wasCancelled = false }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try self.run(executable: executable,
                                                modelPath: modelPath, wav: wav,
                                                prompt: prompt)
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func run(executable: URL, modelPath: String, wav: URL,
                     prompt: String) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "-m", modelPath,
            "-f", wav.path,
            "-nt",              // no timestamps
            "-np",              // no prints
            "-sns",             // suppress non-speech tokens
            "-l", language,
            "-t", String(threads),
        ]
        // Biases the decoder before it goes wrong. Measured: this alone fixed
        // Mikhail→Michael and Kanji→Kandji. Withheld where it cannot help and has
        // been measured to hurt — see `DecoderHint`.
        let hint = DecoderHint.filtered(prompt, forLanguage: language)
        if !hint.isEmpty { process.arguments? += ["--prompt", hint] }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        lock.withLock { self.process = process }
        defer { lock.withLock { self.process = nil } }

        try process.run()

        // Drain both pipes concurrently or a chatty stderr deadlocks the child.
        let sink = PipeSink()
        let group = DispatchGroup()
        for (pipe, isOut) in [(outPipe, true), (errPipe, false)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let d = pipe.fileHandleForReading.readDataToEndOfFile()
                sink.store(d, isStdout: isOut)
                group.leave()
            }
        }

        process.waitUntilExit()
        group.wait()
        let (outData, errData) = sink.contents

        if lock.withLock({ wasCancelled }) { throw TranscriptionError.cancelled }

        guard process.terminationStatus == 0 else {
            let tail = String(decoding: errData, as: UTF8.self)
                .split(separator: "\n").suffix(3).joined(separator: " ")
            throw TranscriptionError.processFailed(exitCode: process.terminationStatus,
                                                  stderrTail: tail)
        }

        let text = Self.cleanTranscript(String(decoding: outData, as: UTF8.self))
        guard !text.isEmpty else { throw TranscriptionError.emptyResult }
        return text
    }

    public func use(language: DictationLanguage) {
        lock.withLock { chosenLanguage = language }
    }

    public func cancel() {
        lock.withLock {
            wasCancelled = true
            process?.terminate()
        }
    }

    // MARK: - Helpers

    /// Configured absolute path, then PATH, then the usual Homebrew prefixes.
    public static func resolveBinary(_ configured: String) -> URL? {
        let fm = FileManager.default
        if configured.contains("/") {
            let expanded = Config.expand(configured)
            return fm.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }

        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        for dir in pathDirs + ["/opt/homebrew/bin", "/usr/local/bin"] {
            let candidate = dir + "/" + configured
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Strips whisper's non-speech annotations and folds the multi-line output
    /// into the single paragraph a dictation user expects.
    /// Kept as the name the tests and the CLI path already use.
    public static func cleanTranscript(_ raw: String) -> String { Transcript.clean(raw) }
}
