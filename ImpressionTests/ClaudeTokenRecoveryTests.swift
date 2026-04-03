import XCTest
@testable import ImpressionMac

final class ClaudeTokenRecoveryTests: XCTestCase {

    func testCredentialManagerPrefersClaudeKeychainOverMirrorToken() {
        let expiry = Int64((Date().addingTimeInterval(600).timeIntervalSince1970) * 1000)
        let mirror = ImpressionMac.OAuthCredentials(
            accessToken: "mirror-token",
            refreshToken: nil,
            expiresAt: expiry,
            scopes: nil
        )
        let local = ImpressionMac.OAuthCredentials(
            accessToken: "local-token",
            refreshToken: "refresh-token",
            expiresAt: expiry,
            scopes: ["user:profile"]
        )

        let manager = ImpressionMac.CredentialManager(
            credentialReader: {
                ImpressionMac.ResolvedCredentialSources(
                    claudeCodeCredentials: local,
                    legacyClaudeCodeCredentials: nil,
                    fileCredentials: nil,
                    legacyFileCredentials: nil,
                    mirrorCredentials: mirror
                )
            },
            onChange: { _, _ in }
        )

        XCTAssertEqual(manager.readCredentials()?.accessToken, "local-token")
    }

    func testResolvedCredentialSourcesFallsBackToMirrorWhenLocalSourcesAreMissing() {
        let mirror = ImpressionMac.OAuthCredentials(
            accessToken: "mirror-token",
            refreshToken: nil,
            expiresAt: Int64((Date().addingTimeInterval(600).timeIntervalSince1970) * 1000),
            scopes: nil
        )

        let sources = ImpressionMac.ResolvedCredentialSources(
            claudeCodeCredentials: nil,
            legacyClaudeCodeCredentials: nil,
            fileCredentials: nil,
            legacyFileCredentials: nil,
            mirrorCredentials: mirror
        )

        XCTAssertEqual(sources.preferredMacCredentials?.accessToken, "mirror-token")
    }

    func testResolvedCredentialSourcesSkipsExpiredLocalCredentialsForValidMirror() {
        let local = ImpressionMac.OAuthCredentials(
            accessToken: "expired-local-token",
            refreshToken: "refresh-token",
            expiresAt: Int64((Date().addingTimeInterval(-60).timeIntervalSince1970) * 1000),
            scopes: nil
        )
        let mirror = ImpressionMac.OAuthCredentials(
            accessToken: "mirror-token",
            refreshToken: nil,
            expiresAt: Int64((Date().addingTimeInterval(600).timeIntervalSince1970) * 1000),
            scopes: nil
        )

        let sources = ImpressionMac.ResolvedCredentialSources(
            claudeCodeCredentials: local,
            legacyClaudeCodeCredentials: nil,
            fileCredentials: nil,
            legacyFileCredentials: nil,
            mirrorCredentials: mirror
        )

        XCTAssertEqual(sources.preferredMacCredentials?.accessToken, "mirror-token")
    }

    func testWritingMirroredTokenWithoutExpiryClearsStaleExpiry() {
        let mirrorStore = InMemoryCredentialMirrorStore()
        let cloudSync = ImpressionMac.CloudSyncService(mirrorStore: mirrorStore)
        let staleExpiry = Date(timeIntervalSince1970: 1_700_000_000)

        mirrorStore.token = "mirror-token"
        mirrorStore.expiry = staleExpiry

        XCTAssertEqual(cloudSync.readCredentialsFromMirror()?.accessToken, "mirror-token")
        XCTAssertEqual(cloudSync.readCredentialsFromMirror()?.expiresAtDate, staleExpiry)

        _ = cloudSync.writeTokenToKeychain("mirror-token-without-expiry")

        XCTAssertEqual(cloudSync.readCredentialsFromMirror()?.accessToken, "mirror-token-without-expiry")
        XCTAssertNil(cloudSync.readCredentialsFromMirror()?.expiresAtDate)
    }

    func testCredentialManagerReEmitsWhenExpiryChangesWithoutTokenChange() {
        let mirrorStore = InMemoryCredentialMirrorStore()
        let cloudSync = ImpressionMac.CloudSyncService(mirrorStore: mirrorStore)

        let expiry1Millis = Int64((Date().addingTimeInterval(600).timeIntervalSince1970 * 1000).rounded(.down))
        let expiry2Millis = Int64((Date().addingTimeInterval(1200).timeIntervalSince1970 * 1000).rounded(.down))
        let expiry1 = Date(timeIntervalSince1970: Double(expiry1Millis) / 1000)
        let expiry2 = Date(timeIntervalSince1970: Double(expiry2Millis) / 1000)
        let token = "mirror-token"

        let sources1 = ImpressionMac.ResolvedCredentialSources(
            claudeCodeCredentials: nil,
            legacyClaudeCodeCredentials: nil,
            fileCredentials: nil,
            legacyFileCredentials: nil,
            mirrorCredentials: ImpressionMac.OAuthCredentials(
                accessToken: token,
                refreshToken: nil,
                expiresAt: expiry1Millis,
                scopes: nil
            )
        )

        let sources2 = ImpressionMac.ResolvedCredentialSources(
            claudeCodeCredentials: nil,
            legacyClaudeCodeCredentials: nil,
            fileCredentials: nil,
            legacyFileCredentials: nil,
            mirrorCredentials: ImpressionMac.OAuthCredentials(
                accessToken: token,
                refreshToken: nil,
                expiresAt: expiry2Millis,
                scopes: nil
            )
        )

        let expectation = expectation(description: "re-emits on expiry change")
        expectation.expectedFulfillmentCount = 2
        let recorder = EmittedExpiryRecorder()

        let observingManager = ImpressionMac.CredentialManager(
            cloudSyncService: cloudSync,
            onChange: { _, expiry in
                if let expiry {
                    recorder.append(expiry)
                }
                expectation.fulfill()
            }
        )

        observingManager.reconcileResolvedSources(sources1)
        observingManager.reconcileResolvedSources(sources2)

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(recorder.expiries, [expiry1, expiry2])
    }

    func testOAuthCredentialsHasUsableRefreshToken() {
        let creds = ImpressionMac.OAuthCredentials(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiresAt: Int64((Date().addingTimeInterval(-60).timeIntervalSince1970) * 1000),
            scopes: nil
        )

        XCTAssertTrue(creds.isExpired)
        XCTAssertTrue(creds.hasRefreshToken)
    }
}

private final class InMemoryCredentialMirrorStore: ImpressionMac.CredentialMirrorStore {
    var token: String?
    var expiry: Date?

    func writeToken(_ token: String) -> Bool {
        self.token = token
        return true
    }

    func readToken() -> String? {
        token
    }

    func deleteToken() -> Bool {
        token = nil
        return true
    }

    func writeExpiry(_ date: Date) {
        expiry = date
    }

    func clearExpiry() {
        expiry = nil
    }

    func readExpiry() -> Date? {
        expiry
    }
}

private final class EmittedExpiryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date] = []

    func append(_ expiry: Date) {
        lock.lock()
        values.append(expiry)
        lock.unlock()
    }

    var expiries: [Date] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
