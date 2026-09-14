import Foundation

public enum LogLevel: String, Sendable, CustomStringConvertible {
    case debug, info, warning, error
    public var description: String { rawValue }
}

public protocol Logging: AnyObject, Sendable {
    func log(_ level: LogLevel, _ message: String)
}

public extension Logging {
    func info(_ m: String) { log(.info, m) }
    func warn(_ m: String) { log(.warning, m) }
    func error(_ m: String) { log(.error, m) }
}

/// Appends to `~/Library/Logs/Rawi/rawi.log`, rotating at 5 MB.
/// Secrets are never passed to this type — see the Global Constraints in the plan.
public final class FileLogger: Logging, @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let maxBytes: Int
    private let alsoPrint: Bool

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Rawi/rawi.log")
    }

    public init(url: URL = FileLogger.defaultURL,
                maxBytes: Int = 5 * 1024 * 1024,
                alsoPrint: Bool = false) {
        self.url = url
        self.maxBytes = maxBytes
        self.alsoPrint = alsoPrint
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func log(_ level: LogLevel, _ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) [\(level.rawValue)] \(message)\n"
        if alsoPrint { FileHandle.standardError.write(Data(line.utf8)) }

        lock.withLock {
            rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    private func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        let rotated = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }
}


/// For code paths constructed without a logger, such as a factory called from a
/// test. Says nothing rather than forcing every caller to own a log.
public final class SilentLog: Logging, @unchecked Sendable {
    public init() {}
    public func log(_ level: LogLevel, _ message: String) {}
}
