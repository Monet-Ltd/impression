import Foundation
import Security

/// Handles iCloud Keychain (token sync) and NSUbiquitousKeyValueStore (usage data sync).
final class CloudSyncService: @unchecked Sendable {
    static let shared = CloudSyncService()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
        kvStore.synchronize()
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
        deleteTokenFromKeychain()

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

    func readTokenFromKeychain() -> String? {
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

    @discardableResult
    func deleteTokenFromKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainService,
            kSecAttrAccount as String: AppConstants.keychainAccount,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Token expiry tracking (for manual paste on iOS)

    func writeTokenExpiry(_ date: Date) {
        kvStore.set(date.timeIntervalSince1970, forKey: "com.impression.tokenExpiresAt")
        kvStore.synchronize()
    }

    func readTokenExpiry() -> Date? {
        let ts = kvStore.double(forKey: "com.impression.tokenExpiresAt")
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}
