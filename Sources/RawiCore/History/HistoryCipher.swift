import CryptoKit
import Foundation
import Security

/// Seals history lines so the file on disk is not a readable record of everything
/// you have said.
public protocol HistoryCipher: Sendable {
    func seal(_ plaintext: Data) throws -> Data
    func open(_ sealed: Data) throws -> Data
}

public enum HistoryCipherError: Error, Equatable {
    case keychain(OSStatus)
    case malformed
}

/// AES-GCM with a key kept in a private file, apart from the history it seals.
///
/// Why a file and not the login keychain. The keychain was tried first and is the
/// stronger place, but on a Mac without an Apple developer signature macOS ties
/// keychain access to the exact build, so every rebuild or update of Rawi made the
/// system ask for permission at launch — measured as 7 to 24 seconds of a stalled
/// launch waiting on that dialog. The keychain that avoids this needs a developer
/// team entitlement (it answers -34018 without one). Once Rawi is signed with one,
/// that is where the key belongs.
///
/// What the file protects against, stated plainly: the history being read on its
/// own — by search, by a sync or upload of that file, by a copy sent somewhere by
/// mistake, by another account on this Mac. The key file is readable only by your
/// account, excluded from Time Machine and from Spotlight. It does not protect
/// against someone who has your whole home folder, or software running as you.
public final class FileKeyHistoryCipher: HistoryCipher, @unchecked Sendable {
    private let key: SymmetricKey

    public static var defaultURL: URL {
        Config.supportDirectory.appendingPathComponent("Keys", isDirectory: true)
            .appendingPathComponent("history.key")
    }

    /// `migrate` supplies an existing key the first time, so history sealed under
    /// it stays readable. It is asked only when no key file exists yet.
    public init(url: URL = FileKeyHistoryCipher.defaultURL,
                migrate: () -> SymmetricKey? = { nil }) throws {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: url), data.count == 32 {
            key = SymmetricKey(data: data)
            return
        }
        let chosen = migrate() ?? SymmetricKey(size: .bits256)
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        // Spotlight never indexes the folder the key lives in.
        fm.createFile(atPath: directory.appendingPathComponent(".metadata_never_index").path,
                      contents: nil)
        let bytes = chosen.withUnsafeBytes { Data($0) }
        guard fm.createFile(atPath: url.path, contents: bytes,
                            attributes: [.posixPermissions: 0o600]) else {
            throw HistoryCipherError.malformed
        }
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(excluded)
        var excludedDirectory = URLResourceValues()
        excludedDirectory.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(excludedDirectory)
        key = chosen
    }

    public func seal(_ plaintext: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw HistoryCipherError.malformed
        }
        return combined
    }

    public func open(_ sealed: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
}

/// The key an earlier build kept in the login keychain, read once so the history
/// it sealed can still be opened, then removed from the keychain.
public enum LegacyKeychainHistoryKey {
    /// The old identifier on purpose. This names a keychain item an earlier build
    /// already wrote; renaming the lookup would orphan the very key it exists to
    /// find, and with it the history that key opens.
    static let service = "com.welaghil.rawi.history"
    static let account = "history-key-v1"

    public static func takeIfPresent() -> SymmetricKey? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var query = base
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else { return nil }
        SecItemDelete(base as CFDictionary)
        return SymmetricKey(data: data)
    }
}

/// For tests: the same sealing, with a key that only ever lives in memory.
public struct InMemoryHistoryCipher: HistoryCipher {
    private let key: SymmetricKey
    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) { self.key = key }
    public func seal(_ plaintext: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw HistoryCipherError.malformed
        }
        return combined
    }
    public func open(_ sealed: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
}
