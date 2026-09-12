import Foundation

/// One dictation, as it happened.
///
/// Both the cleaned text and what whisper actually heard are kept, because when
/// something comes out wrong the raw transcript is the evidence — and because you
/// remember what you *said*, which is what search needs to match against.
///
/// Audio is never recorded. The WAV is deleted as soon as the text is inserted.
public struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let at: Date
    public let cleaned: String
    public let raw: String
    public let script: Script
    /// The rule that shaped this dictation. The URL that matched it is
    /// deliberately not stored — see BrowserContext.
    public let destination: String?
    public let appName: String?
    public let bundleID: String?
    public let durationSeconds: Double
    public let peakLevel: Double
    /// Cleanup was discarded and the raw transcript used instead.
    public let guardRejected: Bool

    public init(id: UUID = UUID(), at: Date, cleaned: String, raw: String,
                destination: String? = nil, script: Script,
                appName: String?, bundleID: String?, durationSeconds: Double,
                peakLevel: Double, guardRejected: Bool) {
        self.id = id
        self.at = at
        self.cleaned = cleaned
        self.raw = raw
        self.script = script
        self.destination = destination
        self.appName = appName
        self.bundleID = bundleID
        self.durationSeconds = durationSeconds
        self.peakLevel = peakLevel
        self.guardRejected = guardRejected
    }

    public var wasCleaned: Bool { cleaned != raw }

    public var timestamp: String {
        let f = DateFormatter(); f.dateFormat = "H:mm"
        return f.string(from: at)
    }

    public var day: String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: at)
    }

    /// One line, whatever the transcript did.
    public var oneLine: String {
        cleaned.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

public struct HistorySettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var limit: Int
    /// Ships non-empty. A password manager and a private-message client are where
    /// a plaintext log is a genuine liability, so they are excluded out of the box
    /// rather than waiting for the user to think of it.
    public var excludedBundleIDs: [String]

    public init(enabled: Bool, limit: Int, excludedBundleIDs: [String]) {
        self.enabled = enabled
        self.limit = limit
        self.excludedBundleIDs = excludedBundleIDs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaultHistory
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? d.limit
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? d.excludedBundleIDs
    }

    public func excludes(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        let lower = bundleID.lowercased()
        return excludedBundleIDs.contains { lower.contains($0.lowercased()) }
    }
}
