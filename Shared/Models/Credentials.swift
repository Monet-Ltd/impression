import Foundation

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
}
