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
        // Not a dictation model: the language detector. Small on purpose — it only
        // has to say which language it heard, before the real model transcribes.
        WhisperModel(id: "base", filename: "ggml-base.bin",
                     displayName: "Base (language detection)", approxBytes: 147_951_465,
                     multilingual: true),
        WhisperModel(id: "base.en", filename: "ggml-base.en.bin",
                     displayName: "Base (English only)", approxBytes: 147_964_211,
                     multilingual: false),
    ]

    public static var recommended: WhisperModel { known[0] }
    /// The detector the one-key-for-both-languages design depends on.
    public static var detector: WhisperModel { model(id: "base")! }

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

    /// Downloads a model to disk, reporting 0...1 progress.
    ///
    /// A download task writes straight to a temporary file and reports progress as
    /// it goes. The previous version iterated the response one byte at a time,
    /// which for the 574 MB default model meant hundreds of millions of async
    /// steps on the first run — minutes of CPU before anyone could dictate. The
    /// file is moved into place only on success, so an interrupted download can
    /// never look like an installed model.
    public static func download(_ model: WhisperModel,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = url(for: model)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = try await DownloadWithProgress.fetch(model.downloadURL,
                                                             expected: model.approxBytes,
                                                             progress: progress)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress(1)
        return destination
    }
}

/// One download, with progress, as an async call.
final class DownloadWithProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expected: Int
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, any Error>?
    private let lock = NSLock()

    private init(expected: Int, progress: @escaping @Sendable (Double) -> Void) {
        self.expected = expected
        self.progress = progress
    }

    static func fetch(_ url: URL, expected: Int,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadWithProgress(expected: expected, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.lock.withLock { delegate.continuation = continuation }
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private func finish(_ result: Result<URL, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<URL, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) : Double(expected)
        progress(min(1, Double(totalBytesWritten) / max(total, 1)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(ModelStoreError.downloadFailed("HTTP \(http.statusCode)")))
            return
        }
        // The system deletes `location` when this returns, so it is moved first.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawi-\(UUID().uuidString).download")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(ModelStoreError.downloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(ModelStoreError.downloadFailed(error.localizedDescription))) }
    }
}
