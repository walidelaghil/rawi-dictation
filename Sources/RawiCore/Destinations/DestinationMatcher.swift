import Foundation

public enum DestinationMatcher {
    /// The most specific enabled rule, or nil.
    ///
    /// Specificity is ordered deliberately: a URL pattern beats a bundle-only
    /// rule, and among URL patterns the longer one wins. That last part is the
    /// entire reason a Slack DM can be treated differently from a Slack channel —
    /// `…/client/*/D*` is longer than `…/client/*`.
    public static func match(bundleID: String?, url: String?,
                             rules: [DestinationRule]) -> DestinationRule? {
        rules
            .filter { $0.enabled }
            .filter { rule in
                if !rule.bundleIDs.isEmpty {
                    guard let bundleID, rule.bundleIDs.contains(bundleID) else { return false }
                }
                // A URL pattern constrains browsers only. One rule can therefore
                // cover "the Slack app, or slack.com in a browser" — in the native
                // app there is no URL to match, and requiring one would mean the
                // rule silently never fired there.
                if let pattern = rule.urlPattern, isBrowser(bundleID) {
                    guard let url, globMatches(pattern, url) else { return false }
                }
                return true
            }
            .max { $0.specificity < $1.specificity }
    }

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Browsers.bundleIDs.contains(bundleID)
    }

    /// `*` matches any run of characters. Anchored at both ends, so a pattern for
    /// `*app.slack.com/client/*` cannot be satisfied by a lookalike host appended
    /// to something else.
    static func globMatches(_ pattern: String, _ value: String) -> Bool {
        let parts = pattern.components(separatedBy: "*")
        guard parts.count > 1 else { return pattern == value }

        var index = value.startIndex
        // A pattern not starting with * must match from the beginning.
        if let first = parts.first, !first.isEmpty {
            guard value.hasPrefix(first) else { return false }
            index = value.index(index, offsetBy: first.count)
        }
        // ...and one not ending with * must reach the end.
        if let last = parts.last, !last.isEmpty {
            guard value.hasSuffix(last) else { return false }
        }
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let found = value.range(of: part, range: index..<value.endIndex)
            else { return false }
            index = found.upperBound
        }
        if let last = parts.last, !last.isEmpty, parts.count > 2 {
            guard let found = value.range(of: last, range: index..<value.endIndex),
                  found.upperBound == value.endIndex else { return false }
        }
        return true
    }
}
