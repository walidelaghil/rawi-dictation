import AppKit
import ApplicationServices

/// Watches the text Rawi just typed, so a spelling you fix is learned.
@MainActor
public protocol EditWatching: AnyObject {
    /// `inserted` was just pasted into the focused field.
    func watch(inserted: String, appName: String?)
    /// Take one last look and stop. Called when the next dictation starts, since
    /// that one may type into the same field and move everything.
    func flush()
}

/// Reads back, through Accessibility, the stretch of a text field Rawi typed.
///
/// What it reads and keeps is deliberately small. It never reads a whole field
/// into memory for longer than one comparison, never logs field text, and keeps
/// only the corrected word. It finds the dictation by the field's own text on
/// either side of it — forty characters each way — so edits elsewhere in the
/// document are never looked at, and if those anchors change, it stops rather
/// than guess.
@MainActor
public final class SystemEditWatcher: EditWatching {
    public var onCorrection: ((Correction, String?) -> Void)?
    /// Where the watch lost track, for the log. Never carries field text.
    public var onNote: ((String) -> Void)?
    public var isOrdinaryWord: (String) -> Bool = SpellCheck.isOrdinaryEnglish

    private struct Watch {
        let element: AXUIElement
        let inserted: String
        let app: String?
        let before: String
        let after: String
        let start: Int                  // UTF-16 offset where the dictation began
        var learned: Set<String> = []
        /// Corrections seen on the previous look, not yet confirmed.
        var seen: Set<String> = []
    }

    private var current: Watch?
    private var timers: [Timer] = []

    /// When to look. People fix a word as soon as they read it, or not at all; three
    /// looks inside a minute catch that without watching a field indefinitely.
    ///
    /// A correction is learned only when two looks in a row agree. The first one
    /// that learned anything for real caught you halfway through retyping "Rawal"
    /// as "Rawi" and taught the dictionary "Raw". The last look, taken when you
    /// start the next dictation, needs no second: you are not editing then.
    static let checks: [TimeInterval] = [4, 10, 20, 45, 60]
    /// How long the target app takes to act on the synthetic ⌘V.
    static let settle: TimeInterval = 0.5
    static let anchorLength = 40

    public init() {}

    public func watch(inserted: String, appName: String?) {
        flush()
        guard AXIsProcessTrusted(), inserted.count >= 3 else { return }
        guard let element = Self.focusedElement() else {
            onNote?("no focused field to watch"); return
        }
        schedule(Self.settle) { [weak self] in
            self?.anchor(element, inserted: inserted, app: appName, attempt: 1)
        }
    }

    public func flush() {
        if current != nil { check(final: true) }
        stop()
    }

    private func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
        current = nil
    }

    private func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timers.append(timer)
    }

    /// Finds where the paste landed and remembers the text around it.
    /// Tries a few times: a busy app can take well over the settle time to act on
    /// the paste, and giving up on the first empty read lost real corrections.
    static let anchorAttempts = 4

    private func anchor(_ element: AXUIElement, inserted: String, app: String?, attempt: Int) {
        func retry(_ reason: String) {
            guard attempt < Self.anchorAttempts else { onNote?(reason); return }
            schedule(Double(attempt) * 0.6) { [weak self] in
                self?.anchor(element, inserted: inserted, app: app, attempt: attempt + 1)
            }
        }
        guard let value = Self.value(of: element) else {
            retry("the field would not share its text"); return
        }
        let text = value as NSString
        var start = NSNotFound
        // The caret sits at the end of what was pasted.
        if let caret = Self.caret(of: element), caret >= inserted.utf16.count,
           caret <= text.length,
           Self.sameWords(text.substring(with: NSRange(location: caret - inserted.utf16.count,
                                                       length: inserted.utf16.count)), inserted) {
            start = caret - inserted.utf16.count
        } else {
            // Some fields move the caret or normalise whitespace; fall back to the
            // last place the dictation appears.
            let found = text.range(of: inserted, options: .backwards)
            start = found.location
        }
        guard start != NSNotFound else {
            retry("could not find the dictation in the field (\(text.length) characters)"); return
        }
        let end = start + inserted.utf16.count
        let beforeStart = max(0, start - Self.anchorLength)
        let afterEnd = min(text.length, end + Self.anchorLength)
        current = Watch(element: element, inserted: inserted, app: app,
                        before: text.substring(with: NSRange(location: beforeStart, length: start - beforeStart)),
                        after: text.substring(with: NSRange(location: end, length: afterEnd - end)),
                        start: start)
        onNote?("watching \(inserted.utf16.count) characters at offset \(start)")
        for delay in Self.checks.map({ $0 - Self.settle }) {
            schedule(delay) { [weak self] in self?.check() }
        }
        schedule(Self.checks.last! - Self.settle + 0.1) { [weak self] in self?.stop() }
    }

    private func check(final: Bool = false) {
        guard var watch = current else { return }
        guard let value = Self.value(of: watch.element) else {
            onNote?("the field is gone"); return
        }
        guard let region = Self.region(in: value as NSString, watch: watch) else {
            onNote?("the text around the dictation changed; not guessing"); return
        }
        let found = EditLearner.corrections(inserted: watch.inserted, current: region,
                                            isOrdinaryWord: isOrdinaryWord)
        let keys = Set(found.map { "\($0.heard.lowercased())→\($0.fixed)" })
        for correction in found {
            let key = "\(correction.heard.lowercased())→\(correction.fixed)"
            guard !watch.learned.contains(key), final || watch.seen.contains(key) else { continue }
            watch.learned.insert(key)
            onCorrection?(correction, watch.app)
        }
        // Only what this look saw counts toward the next: a half-typed word that has
        // since moved on is forgotten.
        watch.seen = keys
        current = watch
    }

    /// The dictation as it reads now, between the field text that surrounded it.
    private static func region(in text: NSString, watch: Watch) -> String? {
        func nearest(_ needle: String, from: Int, to target: Int) -> NSRange? {
            guard !needle.isEmpty else { return nil }
            var best: NSRange?
            var search = NSRange(location: from, length: text.length - from)
            while search.length > 0 {
                let hit = text.range(of: needle, options: [], range: search)
                guard hit.location != NSNotFound else { break }
                if best == nil || abs(hit.location - target) < abs(best!.location - target) { best = hit }
                search = NSRange(location: hit.location + 1, length: text.length - hit.location - 1)
            }
            return best
        }
        let beginning: Int
        if watch.before.isEmpty {
            beginning = 0
        } else {
            guard let hit = nearest(watch.before, from: 0,
                                    to: watch.start - watch.before.utf16.count) else { return nil }
            beginning = hit.location + hit.length
        }
        let ending: Int
        if watch.after.isEmpty {
            ending = text.length
        } else {
            guard let hit = nearest(watch.after, from: beginning,
                                    to: watch.start + watch.inserted.utf16.count) else { return nil }
            ending = hit.location
        }
        guard ending >= beginning,
              ending - beginning <= watch.inserted.utf16.count * 2 + 80 else { return nil }
        return text.substring(with: NSRange(location: beginning, length: ending - beginning))
    }

    private static func sameWords(_ a: String, _ b: String) -> Bool {
        EditLearner.words(a) == EditLearner.words(b)
    }

    /// Verification only, driven by `--trigger editSelfTest`: stands in for your
    /// hand, replacing `from` with `to` in the focused field the way a correction
    /// would. Never called by the dictation path.
    public static func simulateCorrection(from: String, to: String) -> String {
        guard let element = focusedElement() else { return "no focused element" }
        guard let value = value(of: element) else { return "no value" }
        guard value.contains(from) else {
            return "value (\(value.count) chars) has no “\(from)”; starts “\(value.prefix(50))”"
        }
        let edited = value.replacingOccurrences(of: from, with: to)
        let status = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString,
                                                  edited as CFString)
        return status == .success ? "applied" : "set failed (AXError \(status.rawValue))"
    }

    // MARK: - Accessibility

    private static func focusedElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let element = ref as! AXUIElement
        // Never a password field, whatever else is true.
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &role)
        if (role as? String) == kAXSecureTextFieldSubrole { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    nonisolated static func value(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        let direct = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref)
            == .success ? ref as? String : nil
        if let direct, !direct.isEmpty { return direct }
        // Web editors (Notion, and contenteditable fields generally) often answer
        // the value with an empty string and keep the text in their children. They
        // do answer "the characters in this range", which reads the same text.
        var countRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString,
                                            &countRef) == .success,
              let count = countRef as? Int, count > 0 else { return direct }
        var range = CFRange(location: 0, length: count)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return direct }
        var textRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &textRef)
                == .success, let text = textRef as? String else { return direct }
        return text
    }

    private static func caret(of element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range) else { return nil }
        return range.location + range.length
    }
}
