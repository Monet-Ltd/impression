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
