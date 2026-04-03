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

        let manager = CredentialManager(
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
