import Foundation

public struct WhisperModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let filename: String
    public let displayName: String
    public let approxBytes: Int
    public let multilingual: Bool

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    /// Human-readable size, for the model picker and the doctor.
    public var approxSize: String {
        String(format: "%.0f MB", Double(approxBytes) / 1_048_576)
    }
}

public enum ModelStoreError: Error, LocalizedError {
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let m): "Model download failed: \(m)"
        }
    }
}

/// Knows which whisper models exist, which are on disk, and how to fetch one.
///
/// `recommended` is multilingual on purpose: the v1 default was English-only and
/// did not degrade on Arabic — it failed outright.
public enum ModelStore {
    public static let known: [WhisperModel] = [
        WhisperModel(id: "large-v3-turbo-q5_0", filename: "ggml-large-v3-turbo-q5_0.bin",
                     displayName: "Large v3 Turbo", approxBytes: 574_041_195, multilingual: true),
        WhisperModel(id: "small", filename: "ggml-small.bin",
                     displayName: "Small (fast, all languages)",
                     approxBytes: 488_000_000, multilingual: true),
        WhisperModel(id: "medium", filename: "ggml-medium.bin",
                     displayName: "Medium", approxBytes: 1_533_763_059, multilingual: true),
        WhisperModel(id: "small.en", filename: "ggml-small.en.bin",
                     displayName: "Small (English only)", approxBytes: 487_614_201,
                     multilingual: false),
        WhisperModel(id: "base.en", filename: "ggml-base.en.bin",
                     displayName: "Base (English only)", approxBytes: 147_964_211,
                     multilingual: false),
    ]

    public static var recommended: WhisperModel { known[0] }

    public static var directory: URL {
        Config.supportDirectory.appendingPathComponent("models", isDirectory: true)
    }

    public static func url(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.filename)
    }

    public static func isInstalled(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: url(for: model).path)
    }

    public static func installed() -> [WhisperModel] {
        known.filter(isInstalled)
    }

    public static func model(id: String) -> WhisperModel? {
        known.first { $0.id == id }
    }

    /// Resolves a configured model path back to a known model, when it is one.
    public static func model(forPath path: String) -> WhisperModel? {
        let name = (Config.expand(path) as NSString).lastPathComponent
        return known.first { $0.filename == name }
    }

    /// Streams the model to disk, reporting 0...1 progress.
    ///
    /// Downloads land in a `.partial` file and are moved into place only on
    /// success, so an interrupted download can never look like an installed model.
    public static func download(_ model: WhisperModel,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = url(for: model)
        let partial = destination.appendingPathExtension("partial")
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.removeItem(at: partial)
        fm.createFile(atPath: partial.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: partial) else {
            throw ModelStoreError.downloadFailed("could not open \(partial.lastPathComponent)")
        }
        defer { try? handle.close() }

        let (bytes, response) = try await URLSession.shared.bytes(from: model.downloadURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ModelStoreError.downloadFailed("HTTP \(http.statusCode)")
        }
        let expected = response.expectedContentLength > 0
            ? Double(response.expectedContentLength) : Double(model.approxBytes)

        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var written = 0.0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= (1 << 20) {
                try handle.write(contentsOf: buffer)
                written += Double(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(min(1, written / expected))
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Double(buffer.count)
        }
        try handle.close()

        try? fm.removeItem(at: destination)
        try fm.moveItem(at: partial, to: destination)
        progress(1)
        return destination
    }
}
