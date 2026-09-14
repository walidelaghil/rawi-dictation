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
public struct LanguageDetector: Sendable {
    public struct Detection: Sendable, Equatable {
        public let language: String
        public let probability: Double
    }

    private let binary: String
    private let model: String
    private let threads: Int

    /// Below this, the detector is guessing and the caller should pay for a full
    /// `auto` pass rather than pin the wrong language. Being slow is recoverable;
    /// transcribing Arabic as English is not.
    public static let confidenceFloor = 0.6

    public init(binary: String, model: String, threads: Int = 4) {
        self.binary = binary
        self.model = model
        self.threads = threads
    }

    public func detect(wav: URL) async -> Detection? {
        guard FileManager.default.fileExists(atPath: model) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binary, "-m", model, "-f", wav.path,
                             "-dl", "-t", String(threads)]
        // The answer arrives on stderr, alongside the model's own chatter.
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()

        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Self.parse(String(data: data, encoding: .utf8) ?? "")
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
