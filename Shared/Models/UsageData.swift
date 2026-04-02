import Foundation

enum UsageProviderKind: String, Codable, CaseIterable, Identifiable {
    case claudeCode
    case codexCLI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codexCLI: return "Codex"
        }
    }

    var primaryQuotaLabel: String { "Session (5h)" }
    var secondaryQuotaLabel: String { "Weekly (7d)" }

    var requiresToken: Bool {
        self == .claudeCode
    }
}

/// Represents the response from GET /api/oauth/usage
struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageBucket: Codable {
    let utilization: FlexibleDouble
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        return ISO8601DateFormatter().date(from: resetsAt)
            ?? ISO8601DateFormatter.fractional.date(from: resetsAt)
    }
}

/// The API sometimes returns utilization as Int, Double, or String.
/// This wrapper handles all three.
struct FlexibleDouble: Codable, Equatable {
    let value: Double

    init(_ value: Double) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            self.value = d
        } else if let i = try? container.decode(Int.self) {
            self.value = Double(i)
        } else if let s = try? container.decode(String.self), let d = Double(s) {
            self.value = d
        } else {
            self.value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Lightweight snapshot stored in App Group UserDefaults and iCloud KV store.
struct UsageSnapshot: Codable, Equatable {
    let provider: UsageProviderKind
    let sessionUtilization: Double      // 0-100
    let sessionResetsAt: Date?
    let weeklyUtilization: Double       // 0-100
    let weeklyResetsAt: Date?
    let opusUtilization: Double?
    let sonnetUtilization: Double?
    let fetchedAt: Date
    let source: FetchSource
    let primaryLabel: String
    let secondaryLabel: String
    let remainingText: String?

    enum FetchSource: String, Codable {
        case oauthUsage     // from /api/oauth/usage
        case messageHeaders // from /v1/messages response headers
        case icloudCache    // from NSUbiquitousKeyValueStore
        case codexSession   // from Codex local session telemetry
    }

    init(
        provider: UsageProviderKind = .claudeCode,
        sessionUtilization: Double,
        sessionResetsAt: Date?,
        weeklyUtilization: Double,
        weeklyResetsAt: Date?,
        opusUtilization: Double?,
        sonnetUtilization: Double?,
        fetchedAt: Date,
        source: FetchSource,
        primaryLabel: String? = nil,
        secondaryLabel: String? = nil,
        remainingText: String? = nil
    ) {
        self.provider = provider
        self.sessionUtilization = sessionUtilization
        self.sessionResetsAt = sessionResetsAt
        self.weeklyUtilization = weeklyUtilization
        self.weeklyResetsAt = weeklyResetsAt
        self.opusUtilization = opusUtilization
        self.sonnetUtilization = sonnetUtilization
        self.fetchedAt = fetchedAt
        self.source = source
        self.primaryLabel = primaryLabel ?? provider.primaryQuotaLabel
        self.secondaryLabel = secondaryLabel ?? provider.secondaryQuotaLabel
        self.remainingText = remainingText
    }

    static let empty = UsageSnapshot.empty(for: .claudeCode)

    static func empty(for provider: UsageProviderKind) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            sessionUtilization: 0,
            sessionResetsAt: nil,
            weeklyUtilization: 0,
            weeklyResetsAt: nil,
            opusUtilization: nil,
            sonnetUtilization: nil,
            fetchedAt: .distantPast,
            source: .icloudCache
        )
    }

    func withProvider(_ provider: UsageProviderKind) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            sessionUtilization: sessionUtilization,
            sessionResetsAt: sessionResetsAt,
            weeklyUtilization: weeklyUtilization,
            weeklyResetsAt: weeklyResetsAt,
            opusUtilization: opusUtilization,
            sonnetUtilization: sonnetUtilization,
            fetchedAt: fetchedAt,
            source: source,
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel,
            remainingText: remainingText
        )
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
