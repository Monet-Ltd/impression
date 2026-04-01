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
    private let onChange: @Sendable (String, Date?) -> Void
    private var pollingTimer: Timer?
    private var lastKnownToken: String?

    init(onChange: @escaping @Sendable (String, Date?) -> Void) {
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
        if let creds = readFromKeychain() { return creds }
        for path in filePaths {
            if let creds = readFromFile(path) { return creds }
        }
        return nil
    }

    // MARK: - Keychain reading

    private func readFromKeychain() -> OAuthCredentials? {
        for service in AppConstants.claudeKeychainServices {
            if let creds = readKeychainService(service) { return creds }
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
        // Read immediately
        if let creds = readCredentials() {
            lastKnownToken = creds.accessToken
            emitChange(creds)
        }

        // Watch file if it exists
        for path in filePaths {
            if FileManager.default.fileExists(atPath: path) {
                watchFile(path)
                return
            }
        }

        // No file — poll Keychain
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

    // MARK: - Emit change only when token actually differs

    private func emitChange(_ creds: OAuthCredentials) {
        let token = creds.accessToken
        let expiry = creds.expiresAtDate
        // onChange accesses @MainActor-isolated viewModel; must dispatch to main
        let cb = onChange
        DispatchQueue.main.async {
            cb(token, expiry)
        }
        CloudSyncService.shared.writeTokenToKeychain(token)
        if let expiry {
            CloudSyncService.shared.writeTokenExpiry(expiry)
        }
    }

    private func checkAndEmitIfChanged() {
        guard let creds = readCredentials() else { return }

        if creds.accessToken != lastKnownToken {
            NSLog("[Impression] Token changed — re-emitting")
            lastKnownToken = creds.accessToken
            emitChange(creds)
        } else if creds.isExpired {
            NSLog("[Impression] Token expired — Claude Code may not be running")
        }
    }

    // MARK: - Keychain polling (when no credentials file exists)

    private func startKeychainPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndEmitIfChanged()
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
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                self?.checkAndEmitIfChanged()
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
