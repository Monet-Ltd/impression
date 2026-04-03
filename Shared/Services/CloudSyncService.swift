import Foundation
import Security

protocol CredentialMirrorStore: AnyObject {
    func writeToken(_ token: String) -> Bool
    func readToken() -> String?
    func deleteToken() -> Bool
    func writeExpiry(_ date: Date)
    func clearExpiry()
    func readExpiry() -> Date?
}

/// Handles iCloud Keychain (token sync) and NSUbiquitousKeyValueStore (usage data sync).
final class CloudSyncService: @unchecked Sendable {
    static let shared = CloudSyncService()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let mirrorStore: CredentialMirrorStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var kvStoreObserverRegistered = false

    init(
        mirrorStore: CredentialMirrorStore = SystemCredentialMirrorStore()
    ) {
        self.mirrorStore = mirrorStore
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
        kvStoreObserverRegistered = true
        kvStore.synchronize()
    }

    deinit {
        if kvStoreObserverRegistered {
            NotificationCenter.default.removeObserver(self)
        }
    }

    // MARK: - Usage Snapshot (NSUbiquitousKeyValueStore)

    func writeSnapshot(_ snapshot: UsageSnapshot, for provider: UsageProviderKind) {
        guard let data = try? encoder.encode(snapshot) else { return }
        kvStore.set(data, forKey: AppConstants.snapshotStorageKey(for: provider))
        kvStore.synchronize()
    }

    func readSnapshot(for provider: UsageProviderKind) -> UsageSnapshot? {
        guard let data = kvStore.data(forKey: AppConstants.snapshotStorageKey(for: provider)) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    func writeSnapshot(_ snapshot: UsageSnapshot) {
        writeSnapshot(snapshot, for: snapshot.provider)
    }

    func readSnapshot() -> UsageSnapshot? {
        readSnapshot(for: .claudeCode)
    }

    var onSnapshotChanged: ((UsageProviderKind, UsageSnapshot) -> Void)?

    @objc private func kvStoreDidChange(_ notification: Notification) {
        guard let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return }
        for provider in UsageProviderKind.allCases where keys.contains(AppConstants.snapshotStorageKey(for: provider)) {
            if let snapshot = readSnapshot(for: provider) {
                onSnapshotChanged?(provider, snapshot)
            }
        }
    }

    // MARK: - Token (iCloud Keychain)

    func writeTokenToKeychain(_ token: String) -> Bool {
        _ = deleteTokenFromKeychain()
        clearTokenExpiry()
        return mirrorStore.writeToken(token)
    }

    func readTokenFromKeychain() -> String? {
        mirrorStore.readToken()
    }

    @discardableResult
    func deleteTokenFromKeychain() -> Bool {
        mirrorStore.deleteToken()
    }

    // MARK: - Token expiry tracking (for manual paste on iOS)

    func writeTokenExpiry(_ date: Date) {
        mirrorStore.writeExpiry(date)
    }

    func clearTokenExpiry() {
        mirrorStore.clearExpiry()
    }

    func readTokenExpiry() -> Date? {
        mirrorStore.readExpiry()
    }
}

extension CloudSyncService {
    func readCredentialsFromMirror() -> OAuthCredentials? {
        guard let token = readTokenFromKeychain() else { return nil }
        let expiresAt = readTokenExpiry().map { Int64($0.timeIntervalSince1970 * 1000) }
        return OAuthCredentials(
            accessToken: token,
            refreshToken: nil,
            expiresAt: expiresAt,
            scopes: nil
        )
    }
}

private final class SystemCredentialMirrorStore: CredentialMirrorStore {
    private let kvStore: NSUbiquitousKeyValueStore
    private let localDefaults: UserDefaults
    private let tokenExpiryKey = "com.impression.tokenExpiresAt"

    init(
        kvStore: NSUbiquitousKeyValueStore = .default,
        localDefaults: UserDefaults = .standard
    ) {
        self.kvStore = kvStore
        self.localDefaults = localDefaults
    }

    func writeToken(_ token: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainService,
            kSecAttrAccount as String: AppConstants.keychainAccount,
            kSecValueData as String: Data(token.utf8),
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainService,
            kSecAttrAccount as String: AppConstants.keychainAccount,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainService,
            kSecAttrAccount as String: AppConstants.keychainAccount,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func writeExpiry(_ date: Date) {
        let timestamp = date.timeIntervalSince1970
        kvStore.set(timestamp, forKey: tokenExpiryKey)
        localDefaults.set(timestamp, forKey: tokenExpiryKey)
        kvStore.synchronize()
    }

    func clearExpiry() {
        kvStore.removeObject(forKey: tokenExpiryKey)
        localDefaults.removeObject(forKey: tokenExpiryKey)
        kvStore.synchronize()
    }

    func readExpiry() -> Date? {
        let cloudTimestamp = kvStore.double(forKey: tokenExpiryKey)
        if cloudTimestamp > 0 {
            return Date(timeIntervalSince1970: cloudTimestamp)
        }

        let localTimestamp = localDefaults.double(forKey: tokenExpiryKey)
        guard localTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: localTimestamp)
    }
}
