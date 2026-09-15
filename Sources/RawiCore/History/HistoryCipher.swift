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

/// AES-GCM with a key that lives in your login keychain and never on disk beside
/// the file.
///
/// What this protects against, stated plainly: someone who has the history file
/// but not your unlocked login session — a backup copied somewhere, a sync
/// folder, a file sent by mistake, another user account on the Mac. It does not
/// protect against software already running as you, which can ask the keychain
/// for the key the same way Rawi does. FileVault protects the disk as a whole;
/// this protects the file once it leaves the disk.
public final class KeychainHistoryCipher: HistoryCipher, @unchecked Sendable {
    static let service = "com.welaghil.rawi.history"
    static let account = "history-key-v1"

    private let key: SymmetricKey

    public init() throws {
        key = try Self.loadOrCreateKey()
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

    private static func loadOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw HistoryCipherError.keychain(status) }

        let key = SymmetricKey(size: .bits256)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Rawi history key",
            // Never leaves this Mac: not in iCloud Keychain, not in a migrated backup.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw HistoryCipherError.keychain(added) }
        return key
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
