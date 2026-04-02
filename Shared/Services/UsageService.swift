import Foundation

/// Fetches Claude usage data with hybrid strategy:
/// 1. Try GET /api/oauth/usage (free, has resets_at)
/// 2. Fallback: POST /v1/messages with max_tokens=1, parse rate-limit headers
actor UsageService {
    private var currentBackoff: TimeInterval = AppConstants.defaultRefreshInterval
    private var lastSnapshot: UsageSnapshot?

    enum FetchError: Error {
        case noToken
        case rateLimited
        case unauthorized   // 401: token expired or invalid
        case networkError(Error)
        case invalidResponse
    }

    /// Main fetch entry point. Returns a UsageSnapshot or throws.
    func fetch(token: String) async throws -> UsageSnapshot {
        do {
            let snapshot = try await fetchFromOAuthEndpoint(token: token)
            currentBackoff = AppConstants.defaultRefreshInterval
            lastSnapshot = snapshot
            return snapshot
        } catch FetchError.rateLimited {
            // Fallback to Messages API headers
            do {
                let snapshot = try await fetchFromMessageHeaders(token: token)
                currentBackoff = AppConstants.defaultRefreshInterval
                lastSnapshot = snapshot
                return snapshot
            } catch FetchError.rateLimited {
                // Both endpoints rate-limited — exponential backoff
                currentBackoff = min(currentBackoff * 2, AppConstants.maxBackoffInterval)
                if let last = lastSnapshot {
                    return last
                }
                throw FetchError.rateLimited
            }
        }
    }

    var recommendedInterval: TimeInterval {
        currentBackoff
    }

    // MARK: - Primary: /api/oauth/usage

    private func fetchFromOAuthEndpoint(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: AppConstants.usageEndpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConstants.anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw FetchError.rateLimited
        }
        if httpResponse.statusCode == 401 {
            throw FetchError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            throw FetchError.invalidResponse
        }

        let usageResponse = try JSONDecoder().decode(UsageResponse.self, from: data)

        return UsageSnapshot(
            sessionUtilization: usageResponse.fiveHour?.utilization.value ?? 0,
            sessionResetsAt: usageResponse.fiveHour?.resetsAtDate,
            weeklyUtilization: usageResponse.sevenDay?.utilization.value ?? 0,
            weeklyResetsAt: usageResponse.sevenDay?.resetsAtDate,
            opusUtilization: usageResponse.sevenDayOpus?.utilization.value,
            sonnetUtilization: usageResponse.sevenDaySonnet?.utilization.value,
            fetchedAt: Date(),
            source: .oauthUsage
        )
    }

    // MARK: - Fallback: /v1/messages headers

    private func fetchFromMessageHeaders(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: AppConstants.messagesEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConstants.anthropicVersionHeader, forHTTPHeaderField: "anthropic-version")
        request.setValue(AppConstants.anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model": AppConstants.fallbackModel,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw FetchError.rateLimited
        }
        if httpResponse.statusCode == 401 {
            throw FetchError.unauthorized
        }

        // Parse rate-limit headers (0.0 - 1.0 scale, convert to 0-100)
        let sessionUtil = parseHeaderDouble(httpResponse, key: "anthropic-ratelimit-unified-5h-utilization") * 100
        let weeklyUtil = parseHeaderDouble(httpResponse, key: "anthropic-ratelimit-unified-7d-utilization") * 100

        return UsageSnapshot(
            sessionUtilization: sessionUtil,
            sessionResetsAt: lastSnapshot?.sessionResetsAt, // preserve cached resets_at
            weeklyUtilization: weeklyUtil,
            weeklyResetsAt: lastSnapshot?.weeklyResetsAt,
            opusUtilization: lastSnapshot?.opusUtilization,
            sonnetUtilization: lastSnapshot?.sonnetUtilization,
            fetchedAt: Date(),
            source: .messageHeaders
        )
    }

    private func parseHeaderDouble(_ response: HTTPURLResponse, key: String) -> Double {
        guard let value = response.value(forHTTPHeaderField: key),
              let d = Double(value) else { return 0 }
        return d
    }
}

actor CodexUsageService {
    enum FetchError: Error, LocalizedError {
        case noUsageData
        case invalidUsageData

        var errorDescription: String? {
            switch self {
            case .noUsageData:
                return "No Codex usage data found in local sessions"
            case .invalidUsageData:
                return "Unable to parse Codex usage data"
            }
        }
    }

    func fetch() async throws -> UsageSnapshot {
        let rateLimits = try latestRateLimits()

        return UsageSnapshot(
            provider: .codexCLI,
            sessionUtilization: rateLimits.primary.usedPercent,
            sessionResetsAt: rateLimits.primary.resetsAtDate,
            weeklyUtilization: rateLimits.secondary?.usedPercent ?? 0,
            weeklyResetsAt: rateLimits.secondary?.resetsAtDate,
            opusUtilization: nil,
            sonnetUtilization: nil,
            fetchedAt: Date(),
            source: .codexSession,
            primaryLabel: rateLimits.primary.label,
            secondaryLabel: rateLimits.secondary?.label ?? UsageProviderKind.codexCLI.secondaryQuotaLabel,
            remainingText: rateLimits.planType.map { "Plan: \($0.capitalized)" }
        )
    }

    private func latestRateLimits() throws -> CodexRateLimits {
        let sessionURLs = try recentSessionURLs()

        for url in sessionURLs {
            if let rateLimits = try parseLatestRateLimits(in: url) {
                return rateLimits
            }
        }

        throw FetchError.noUsageData
    }

    private func recentSessionURLs() throws -> [URL] {
        let sessionsURL = URL(fileURLWithPath: AppConstants.codexSessionsPath)
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let urls = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }

        return try urls.sorted {
            let lhsDate = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhsDate = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    private func parseLatestRateLimits(in url: URL) throws -> CodexRateLimits? {
        let content = try String(contentsOf: url, encoding: .utf8)
        for line in content.split(separator: "\n").reversed() {
            if let parsed = Self.rateLimits(fromJSONLine: String(line)) {
                return parsed
            }
        }
        return nil
    }

    static func rateLimits(fromJSONLine line: String) -> CodexRateLimits? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(CodexTokenCountEvent.self, from: data),
              event.type == "event_msg",
              event.payload.type == "token_count",
              event.payload.rateLimits.limitID == "codex" else {
            return nil
        }

        return CodexRateLimits(
            primary: .init(
                usedPercent: event.payload.rateLimits.primary.usedPercent,
                resetsAt: event.payload.rateLimits.primary.resetsAt,
                label: "Session (\(event.payload.rateLimits.primary.windowMinutes / 60)h)"
            ),
            secondary: event.payload.rateLimits.secondary.map {
                .init(
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt,
                    label: "Weekly (\($0.windowMinutes / (60 * 24))d)"
                )
            },
            planType: event.payload.rateLimits.planType
        )
    }
}

struct CodexRateLimits: Equatable {
    struct Window: Equatable {
        let usedPercent: Double
        let resetsAt: Int
        let label: String

        var resetsAtDate: Date {
            Date(timeIntervalSince1970: TimeInterval(resetsAt))
        }
    }

    let primary: Window
    let secondary: Window?
    let planType: String?
}

private struct CodexTokenCountEvent: Decodable {
    let type: String
    let payload: CodexTokenCountPayload
}

private struct CodexTokenCountPayload: Decodable {
    let type: String
    let rateLimits: CodexRateLimitPayload

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct CodexRateLimitPayload: Decodable {
    let limitID: String
    let primary: CodexRateLimitWindowPayload
    let secondary: CodexRateLimitWindowPayload?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct CodexRateLimitWindowPayload: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Int

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
