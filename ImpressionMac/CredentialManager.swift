import Foundation
import Security

/// macOS-only: Reads Claude Code OAuth credentials.
/// Tries multiple sources in order:
/// 1. macOS Keychain (service: "Claude Code-credentials")
/// 2. ~/.claude/.credentials.json file
/// 3. ~/.claude/credentials.json file
final class CredentialManager: @unchecked Sendable {
    typealias CredentialReader = @Sendable () -> ResolvedCredentialSources

    enum CredentialUpdate: Equatable {
        case present(token: String, expiresAt: Date?)
        case missing
    }

    private static let defaultFilePaths = [
        NSHomeDirectory() + "/.claude/.credentials.json",
        NSHomeDirectory() + "/.claude/credentials.json",
    ]

    private let filePaths: [String]
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let onChange: @Sendable (CredentialUpdate) -> Void
    private let cloudSyncService: CloudSyncService
    private let credentialReader: CredentialReader
    private var pollingTimer: Timer?

    private struct WatchedCredentialState: Equatable {
        let token: String
        let expiresAt: Date?
    }

    private var lastKnownState: WatchedCredentialState?

    init(
        credentialReader: CredentialReader? = nil,
        cloudSyncService: CloudSyncService = .shared,
        onChange: @escaping @Sendable (CredentialUpdate) -> Void
    ) {
        self.filePaths = Self.defaultFilePaths
        self.cloudSyncService = cloudSyncService
        self.credentialReader = credentialReader ?? { [cloudSyncService] in
            Self.defaultResolvedSources(cloudSyncService: cloudSyncService)
        }
        self.onChange = onChange
    }

    deinit {
        stopWatching()
    }

    func readCredentials() -> OAuthCredentials? {
        resolvedSources().preferredMacCredentials
    }

    func resolvedSources() -> ResolvedCredentialSources {
        credentialReader()
    }

    private static func defaultResolvedSources(cloudSyncService: CloudSyncService) -> ResolvedCredentialSources {
        var keychainCredentials: [String: OAuthCredentials] = [:]
        for service in AppConstants.claudeKeychainServices {
            if let creds = readKeychainService(service) {
                keychainCredentials[service] = creds
            }
        }

        return ResolvedCredentialSources(
            claudeCodeCredentials: keychainCredentials["Claude Code-credentials"],
            legacyClaudeCodeCredentials: keychainCredentials["Claude Code"],
            fileCredentials: readFromFile(defaultFilePaths[0]),
            legacyFileCredentials: readFromFile(defaultFilePaths[1]),
            mirrorCredentials: cloudSyncService.readCredentialsFromMirror()
        )
    }

    private static func readKeychainService(_ service: String) -> OAuthCredentials? {
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

    private static func readFromFile(_ path: String) -> OAuthCredentials? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let file = try? JSONDecoder().decode(CredentialsFile.self, from: data)
        return file?.claudeAiOauth
    }

    func startWatching() {
        reconcileResolvedSources(resolvedSources())

        for path in filePaths {
            if FileManager.default.fileExists(atPath: path) {
                watchFile(path)
                return
            }
        }

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

    // MARK: - Emit change only when token or expiry actually differs
    func reconcileResolvedSources(_ sources: ResolvedCredentialSources) {
        guard let creds = sources.preferredMacCredentials else {
            if lastKnownState != nil {
                lastKnownState = nil
                emitMissingCredentials()
            }
            return
        }

        let state = WatchedCredentialState(
            token: creds.accessToken,
            expiresAt: creds.expiresAtDate
        )
        guard state != lastKnownState else { return }

        lastKnownState = state
        emitChange(creds)
    }

    private func emitChange(_ creds: OAuthCredentials) {
        let token = creds.accessToken
        let expiry = creds.expiresAtDate
        let cb = onChange
        DispatchQueue.main.async {
            cb(.present(token: token, expiresAt: expiry))
        }
        _ = cloudSyncService.writeTokenToKeychain(token)
        if let expiry {
            cloudSyncService.writeTokenExpiry(expiry)
        }
    }

    private func emitMissingCredentials() {
        let cb = onChange
        DispatchQueue.main.async {
            cb(.missing)
        }
    }

    private func checkAndEmitIfChanged() {
        let sources = resolvedSources()
        let creds = sources.preferredMacCredentials
        let state = creds.map {
            WatchedCredentialState(token: $0.accessToken, expiresAt: $0.expiresAtDate)
        }

        if state != lastKnownState {
            if lastKnownState != nil {
                if creds == nil {
                    NSLog("[Impression] Token disappeared — clearing watcher state")
                } else {
                    NSLog("[Impression] Token or expiry changed — re-emitting")
                }
            }
            if let creds {
                lastKnownState = state
                emitChange(creds)
            } else if lastKnownState != nil {
                lastKnownState = nil
                emitMissingCredentials()
            }
        } else if creds?.isExpired == true {
            NSLog("[Impression] Token expired — Claude Code may not be running")
        }
    }

    private func startKeychainPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndEmitIfChanged()
        }
    }

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
