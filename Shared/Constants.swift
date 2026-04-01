import Foundation

enum AppConstants {
    static let appGroupID = "group.com.impression.usage"
    static let iCloudKVStoreKey = "com.impression.usageSnapshot"
    static let keychainService = "com.impression.claude-token"
    static let keychainAccount = "default"

    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let messagesEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let credentialsPath = NSHomeDirectory() + "/.claude/.credentials.json"
    static let claudeKeychainServices = ["Claude Code-credentials", "Claude Code"]

    static let defaultRefreshInterval: TimeInterval = 120
    static let minRefreshInterval: TimeInterval = 60
    static let maxBackoffInterval: TimeInterval = 960 // 16 minutes

    static let warningThresholdDefault: Double = 80
    static let criticalThresholdDefault: Double = 95

    static let anthropicBetaHeader = "oauth-2025-04-20"
    static let anthropicVersionHeader = "2023-06-01"
    static let userAgent = "Impression/1.0"
    static let fallbackModel = "claude-haiku-4-5-20251001"
}
