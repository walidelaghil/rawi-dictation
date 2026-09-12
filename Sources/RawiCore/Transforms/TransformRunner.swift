import AppKit
import Foundation

/// Read/write access to the clipboard, so the runner is testable without one.
public protocol ClipboardAccess: AnyObject {
    var text: String? { get set }
}

public final class SystemClipboard: ClipboardAccess {
    public init() {}
    public var text: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let newValue { pb.setString(newValue, forType: .string) }
        }
    }
}

public enum TransformError: Error, LocalizedError, Equatable {
    case emptyClipboard
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyClipboard: "Copy some text first"
        case .emptyResult: "The model returned nothing"
        }
    }
}

/// Applies a spoken instruction to whatever is on the clipboard.
///
/// A transform is **not** a dictation, and the difference matters: `CleanupGuard`
/// must not run here. The guard exists to stop the model rewriting your words —
/// which is precisely what a transform is asked to do. Its safety comes from
/// elsewhere:
///
///   - the original is handed to history *before* the model is called, so it
///     survives even a crash mid-transform
///   - an empty clipboard is refused before anything runs
///   - on any failure the clipboard is left exactly as it was: never cleared,
///     never half-written
@MainActor
public final class TransformRunner {
    public struct Outcome: Sendable {
        public let transform: Transform?
        public let instruction: String
        public let before: String
        public let after: String
    }

    private let store: TransformStore
    private let rewriter: any CleanupProvider
    private let clipboard: any ClipboardAccess

    /// The clipboard text as it was, published before the model is called.
    public var onOriginal: ((String) -> Void)?

    public init(store: TransformStore,
                rewriter: any CleanupProvider,
                clipboard: any ClipboardAccess = SystemClipboard()) {
        self.store = store
        self.rewriter = rewriter
        self.clipboard = clipboard
    }

    public func run(spoken: String) async throws -> Outcome {
        let before = (clipboard.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !before.isEmpty else { throw TransformError.emptyClipboard }

        let matched = store.match(spoken: spoken)
        // No match is not a failure: the spoken words become the instruction, so
        // the feature is never limited to the transforms someone thought of.
        let instruction = matched?.instruction
            ?? spoken.trimmingCharacters(in: .whitespacesAndNewlines)

        onOriginal?(before)

        let reply = try await rewriter.clean(
            wrapTransform(text: before, instruction: instruction))
        let after = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !after.isEmpty else { throw TransformError.emptyResult }

        clipboard.text = after
        return Outcome(transform: matched, instruction: instruction,
                       before: before, after: after)
    }

    public func cancel() { rewriter.cancel() }
}
