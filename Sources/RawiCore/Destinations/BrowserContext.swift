import AppKit
import Foundation

/// Reads the active tab URL from a scriptable browser.
///
/// Uses Automation (AppleEvents), which is **user-approvable** — unlike
/// Accessibility and Screen Recording, it does not need an administrator. That is
/// what makes page-level destination awareness possible on a managed Mac at all.
///
/// Measured on this machine: Brave answers in 0.15 s, Chrome in 0.16 s, and both
/// return `-1719` when no window is open. The timeout exists for that case and for
/// a browser that is busy — where the right answer is no rule, never a stalled
/// dictation.
///
/// **The URL is matched and discarded.** It is never written to history: a real
/// tab URL here contained a personal email address in a query parameter, and a
/// plaintext log of those is exactly the liability history is capped to avoid.
public enum BrowserContext {
    /// Brave first — it is the browser in use here.
    public static let scriptable: [String: String] = [
        "com.brave.Browser": "Brave Browser",
        "com.google.Chrome": "Google Chrome",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.apple.Safari": "Safari",
    ]

    /// Swift 6 forbids bare mutable statics; the diagnostic state lives in a
    /// locked box rather than being dropped.
    private final class Diagnostics: @unchecked Sendable {
        private let lock = NSLock()
        private var message: String?
        func set(_ value: String?) { lock.withLock { message = value } }
        func get() -> String? { lock.withLock { message } }
    }
    private static let diagnostics = Diagnostics()
    public static var lastError: String? { diagnostics.get() }

    public static func activeURL(bundleID: String?, timeout: TimeInterval = 0.5) -> String? {
        guard let bundleID, let appName = scriptable[bundleID] else { return nil }

        let source = bundleID == "com.apple.Safari"
            ? "tell application \"Safari\" to return URL of front document"
            : "tell application \"\(appName)\" to return URL of active tab of front window"

        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
            box.set(value: value?.stringValue,
                    error: error?[NSAppleScript.errorMessage] as? String)
            semaphore.signal()
        }

        // A browser that does not answer promptly costs the rule, not the dictation.
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            diagnostics.set("\(appName) did not answer within \(timeout)s")
            return nil
        }
        diagnostics.set(box.error)
        guard let url = box.value, !url.isEmpty else { return nil }
        return url
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: String?
        private var _error: String?
        var value: String? { lock.withLock { _value } }
        var error: String? { lock.withLock { _error } }
        func set(value: String?, error: String?) {
            lock.withLock { _value = value; _error = error }
        }
    }
}
