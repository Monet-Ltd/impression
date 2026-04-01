import Foundation
import Security

/// macOS-only: Reads Claude Code OAuth credentials.
/// Tries multiple sources in order:
/// 1. macOS Keychain (service: "Claude Code-credentials")
/// 2. ~/.claude/.credentials.json file
/// 3. ~/.claude/credentials.json file
final class CredentialManager {
    private let filePaths: [String]
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let onChange: (String, Date?) -> Void
    private var pollingTimer: Timer?

    init(onChange: @escaping (String, Date?) -> Void) {
        self.filePaths = [
            NSHomeDirectory() + "/.claude/.credentials.json",
            NSHomeDirectory() + "/.claude/credentials.json",
        ]
        self.onChange = onChange
    }

    deinit {
        stopWatching()
    }

    // MARK: - Read credentials from best available source

    func readCredentials() -> OAuthCredentials? {
        // Try Keychain first
        if let creds = readFromKeychain() {
            return creds
        }
        // Try file paths
        for path in filePaths {
            if let creds = readFromFile(path) {
                return creds
            }
        }
        return nil
    }

    // MARK: - Keychain reading

    private func readFromKeychain() -> OAuthCredentials? {
        // Try the standard service name
        if let creds = readKeychainService("Claude Code-credentials") {
            return creds
        }
        // Try hashed variant (CLI v2.1.52+)
        if let creds = readKeychainService("Claude Code") {
            return creds
        }
        return nil
    }

    private func readKeychainService(_ service: String) -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }

        // The keychain value is the full JSON string
        let file = try? JSONDecoder().decode(CredentialsFile.self, from: data)
        return file?.claudeAiOauth
    }

    // MARK: - File reading

    private func readFromFile(_ path: String) -> OAuthCredentials? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let file = try? JSONDecoder().decode(CredentialsFile.self, from: data)
        return file?.claudeAiOauth
    }

    // MARK: - Watching for changes

    func startWatching() {
        // Read immediately from best source
        if let creds = readCredentials() {
            onChange(creds.accessToken, creds.expiresAtDate)
            CloudSyncService.shared.writeTokenToKeychain(creds.accessToken)
            if let expiry = creds.expiresAtDate {
                CloudSyncService.shared.writeTokenExpiry(expiry)
            }
        }

        // Watch for file changes (if file exists)
        for path in filePaths {
            if FileManager.default.fileExists(atPath: path) {
                watchFile(path)
                return
            }
        }

        // No file found — poll Keychain periodically for token refresh
        startKeychainPolling()
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - Keychain polling (when no credentials file exists)

    private func startKeychainPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let creds = self.readFromKeychain() {
                self.onChange(creds.accessToken, creds.expiresAtDate)
                CloudSyncService.shared.writeTokenToKeychain(creds.accessToken)
                if let expiry = creds.expiresAtDate {
                    CloudSyncService.shared.writeTokenExpiry(expiry)
                }
            }
        }
    }

    // MARK: - File watching

    private func watchFile(_ path: String) {
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .global()
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if let creds = self.readCredentials() {
                    self.onChange(creds.accessToken, creds.expiresAtDate)
                    CloudSyncService.shared.writeTokenToKeychain(creds.accessToken)
                    if let expiry = creds.expiresAtDate {
                        CloudSyncService.shared.writeTokenExpiry(expiry)
                    }
                }
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source.resume()
        dispatchSource = source
    }
}
