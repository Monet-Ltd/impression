import Foundation

/// macOS-only: Reads and watches ~/.claude/.credentials.json for token changes.
final class CredentialManager {
    private let path: String
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let onChange: (String, Date?) -> Void

    init(path: String = AppConstants.credentialsPath, onChange: @escaping (String, Date?) -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit {
        stopWatching()
    }

    /// Read credentials once.
    func readCredentials() -> OAuthCredentials? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let file = try? JSONDecoder().decode(CredentialsFile.self, from: data)
        return file?.claudeAiOauth
    }

    /// Start watching the credentials file for changes.
    func startWatching() {
        // Read immediately
        if let creds = readCredentials() {
            onChange(creds.accessToken, creds.expiresAtDate)
            // Also sync to iCloud Keychain
            CloudSyncService.shared.writeTokenToKeychain(creds.accessToken)
            if let expiry = creds.expiresAtDate {
                CloudSyncService.shared.writeTokenExpiry(expiry)
            }
        }

        // Watch for file changes
        watchFile()
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func watchFile() {
        // If file doesn't exist yet, poll for its creation
        guard FileManager.default.fileExists(atPath: path) else {
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.watchFile()
            }
            return
        }

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .global()
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Small delay to let the write complete
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
