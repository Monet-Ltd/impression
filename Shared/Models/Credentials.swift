import Foundation
#if os(macOS)
import Security
#endif

/// Represents ~/.claude/.credentials.json
struct CredentialsFile: Codable {
    let claudeAiOauth: OAuthCredentials?
}

struct OAuthCredentials: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Int64?   // Unix ms
    let scopes: [String]?

    var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        return Date(timeIntervalSince1970: Double(expiresAt) / 1000.0)
    }

    var isExpired: Bool {
        guard let date = expiresAtDate else { return false }
        return date < Date()
    }

    var timeUntilExpiry: TimeInterval? {
        guard let date = expiresAtDate else { return nil }
        return date.timeIntervalSinceNow
    }

    var hasRefreshToken: Bool {
        guard let refreshToken else { return false }
        return !refreshToken.isEmpty
    }

    var isUsableForMacRecovery: Bool {
        !isExpired
    }
}

struct ResolvedCredentialSources {
    let claudeCodeCredentials: OAuthCredentials?
    let legacyClaudeCodeCredentials: OAuthCredentials?
    let fileCredentials: OAuthCredentials?
    let legacyFileCredentials: OAuthCredentials?
    let mirrorCredentials: OAuthCredentials?

    var preferredMacCredentials: OAuthCredentials? {
        [
            claudeCodeCredentials,
            legacyClaudeCodeCredentials,
            fileCredentials,
            legacyFileCredentials,
        ]
        .compactMap { $0 }
        .first
    }

    var hasAnyLocalClaudeSource: Bool {
        claudeCodeCredentials != nil
        || legacyClaudeCodeCredentials != nil
        || fileCredentials != nil
        || legacyFileCredentials != nil
    }
}

struct ClaudeRefreshResponse: Codable, Equatable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let tokenType: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

enum ClaudeCredentialsSource {
    #if os(macOS)
    private static let filePaths: [String] = [
        NSHomeDirectory() + "/.claude/.credentials.json",
        NSHomeDirectory() + "/.claude/credentials.json",
    ]

    static func readOAuthCredentials() -> OAuthCredentials? {
        if let credentials = readFromKeychain() {
            return credentials
        }

        for path in filePaths {
            if let credentials = readFromFile(path) {
                return credentials
            }
        }

        return nil
    }

    private static func readFromKeychain() -> OAuthCredentials? {
        for service in AppConstants.claudeKeychainServices {
            if let credentials = readKeychainService(service) {
                return credentials
            }
        }
        return nil
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
    #endif
}
