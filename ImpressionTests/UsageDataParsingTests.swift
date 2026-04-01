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
            sessionUtilization: 42.5,
            sessionResetsAt: Date(timeIntervalSince1970: 1743465600),
            weeklyUtilization: 15.0,
            weeklyResetsAt: Date(timeIntervalSince1970: 1743724800),
            opusUtilization: 8.0,
            sonnetUtilization: 3.0,
            fetchedAt: Date(timeIntervalSince1970: 1743379200),
            source: .oauthUsage
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(snapshot, decoded)
    }
}
