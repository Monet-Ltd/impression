import XCTest
@testable import ImpressionMac

final class UsageDataParsingTests: XCTestCase {

    func testParseFullResponse() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 42.5,
            "resets_at": "2026-03-31T15:30:00.000000+00:00"
          },
          "seven_day": {
            "utilization": 15.0,
            "resets_at": "2026-04-03T08:00:00.000000+00:00"
          },
          "seven_day_opus": {
            "utilization": 8.0,
            "resets_at": "2026-04-03T08:00:00.000000+00:00"
          },
          "seven_day_sonnet": {
            "utilization": 3.0,
            "resets_at": "2026-04-03T08:00:00.000000+00:00"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour?.utilization.value, 42.5)
        XCTAssertNotNil(response.fiveHour?.resetsAtDate)
        XCTAssertEqual(response.sevenDay?.utilization.value, 15.0)
        XCTAssertEqual(response.sevenDayOpus?.utilization.value, 8.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization.value, 3.0)
    }

    func testParseIntUtilization() throws {
        let json = """
        { "five_hour": { "utilization": 42, "resets_at": null } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization.value, 42.0)
    }

    func testParseStringUtilization() throws {
        let json = """
        { "five_hour": { "utilization": "42.5", "resets_at": null } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization.value, 42.5)
    }

    func testParseNullBuckets() throws {
        let json = """
        {
          "five_hour": { "utilization": 10, "resets_at": null },
          "seven_day": null,
          "seven_day_opus": null,
          "seven_day_sonnet": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertNotNil(response.fiveHour)
        XCTAssertNil(response.sevenDay)
        XCTAssertNil(response.sevenDayOpus)
    }

    func testParseCredentialsFile() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-oat01-test",
            "refreshToken": "sk-ant-ort01-test",
            "expiresAt": \(Int64((Date().timeIntervalSince1970 + 86400) * 1000)),
            "scopes": ["user:profile"]
          }
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(CredentialsFile.self, from: json)
        XCTAssertEqual(file.claudeAiOauth?.accessToken, "sk-ant-oat01-test")
        XCTAssertNotNil(file.claudeAiOauth?.expiresAtDate)
        XCTAssertFalse(file.claudeAiOauth?.isExpired ?? true) // expires tomorrow
    }

    func testUsageColorThresholds() {
        XCTAssertEqual(UsageColor.from(utilization: 0), .green)
        XCTAssertEqual(UsageColor.from(utilization: 59), .green)
        XCTAssertEqual(UsageColor.from(utilization: 60), .yellow)
        XCTAssertEqual(UsageColor.from(utilization: 79), .yellow)
        XCTAssertEqual(UsageColor.from(utilization: 80), .orange)
        XCTAssertEqual(UsageColor.from(utilization: 94), .orange)
        XCTAssertEqual(UsageColor.from(utilization: 95), .red)
        XCTAssertEqual(UsageColor.from(utilization: 100), .red)
    }

    func testSnapshotCoding() throws {
        let snapshot = UsageSnapshot(
            provider: .codexCLI,
            sessionUtilization: 42.5,
            sessionResetsAt: Date(timeIntervalSince1970: 1743465600),
            weeklyUtilization: 15.0,
            weeklyResetsAt: Date(timeIntervalSince1970: 1743724800),
            opusUtilization: 8.0,
            sonnetUtilization: 3.0,
            fetchedAt: Date(timeIntervalSince1970: 1743379200),
            source: .oauthUsage,
            remainingText: "Plan: Plus"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(snapshot, decoded)
        XCTAssertEqual(decoded.provider, .codexCLI)
        XCTAssertEqual(decoded.remainingText, "Plan: Plus")
    }

    func testProviderDefaults() {
        XCTAssertEqual(UsageProviderKind.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(UsageProviderKind.codexCLI.displayName, "Codex CLI")
        XCTAssertTrue(UsageProviderKind.claudeCode.requiresToken)
        XCTAssertFalse(UsageProviderKind.codexCLI.requiresToken)
        XCTAssertEqual(UsageProviderKind.claudeCode.accentHex, "#C96442")
        XCTAssertEqual(UsageProviderKind.codexCLI.accentHex, "#00D992")
    }

    func testSnapshotPresentationHelpers() {
        let snapshot = UsageSnapshot(
            provider: .codexCLI,
            sessionUtilization: 42,
            sessionResetsAt: nil,
            weeklyUtilization: 15,
            weeklyResetsAt: nil,
            opusUtilization: nil,
            sonnetUtilization: nil,
            fetchedAt: .distantPast,
            source: .codexSession,
            remainingText: "Plan: Plus"
        )

        XCTAssertEqual(snapshot.sourceDisplayName, "Local telemetry")
        XCTAssertEqual(snapshot.normalizedPlanName, "Plus")
    }

    func testParseCodexRateLimitLine() {
        let line = """
        {"timestamp":"2026-04-02T05:30:56.159Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":43.0,"window_minutes":300,"resets_at":1775115417},"secondary":{"used_percent":13.0,"window_minutes":10080,"resets_at":1775702217},"credits":null,"plan_type":"plus"}}}
        """

        let parsed = CodexUsageService.rateLimits(fromJSONLine: line)

        XCTAssertEqual(parsed?.primary.usedPercent, 43.0)
        XCTAssertEqual(parsed?.primary.label, "Session (5h)")
        XCTAssertEqual(parsed?.secondary?.usedPercent, 13.0)
        XCTAssertEqual(parsed?.secondary?.label, "Weekly (7d)")
        XCTAssertEqual(parsed?.planType, "plus")
    }

    @MainActor
    func testClaudeTokenResolutionFallsBackToClaudeCredentials() {
        let fallback = OAuthCredentials(
            accessToken: "sk-ant-oat01-fallback",
            refreshToken: "sk-ant-ort01-fallback",
            expiresAt: Int64((Date().timeIntervalSince1970 + 3600) * 1000),
            scopes: ["user:profile"]
        )

        let resolved = UsageViewModel.resolveClaudeToken(
            syncedToken: nil,
            syncedExpiry: nil,
            fallbackCredentials: fallback
        )

        XCTAssertEqual(resolved.token, "sk-ant-oat01-fallback")
        if case .expiresSoon = resolved.status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected fallback token to remain usable and be marked expiresSoon")
        }
    }
}
