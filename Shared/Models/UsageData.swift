import Foundation

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
    let sessionUtilization: Double      // 0-100
    let sessionResetsAt: Date?
    let weeklyUtilization: Double       // 0-100
    let weeklyResetsAt: Date?
    let opusUtilization: Double?
    let sonnetUtilization: Double?
    let fetchedAt: Date
    let source: FetchSource

    enum FetchSource: String, Codable {
        case oauthUsage     // from /api/oauth/usage
        case messageHeaders // from /v1/messages response headers
        case icloudCache    // from NSUbiquitousKeyValueStore
    }

    static let empty = UsageSnapshot(
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

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
