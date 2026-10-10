import XCTest
@testable import BubbleTaxBarCore

final class LiveUsageNormalizerTests: XCTestCase {
    private func payload() -> [String: Any] {
        ["source": "oauth", "usage": ["updatedAt": "2026-10-08T10:00:00Z",
            "identity": ["loginMethod": "Enterprise", "accountEmail": "PRIVATE@example.com", "accountOrganization": "PRIVATE-ORG"],
            "primary": ["usedPercent": 20, "windowMinutes": 300, "resetsAt": "2026-10-08T12:00:00Z"]]]
    }
    private func normalize(_ row: Any) throws -> (ProviderConnection, [QuotaWindow]) {
        try LiveUsageNormalizer.normalize(JSONSerialization.data(withJSONObject: row), provider: .openai)
    }
    func testMetadataAndQuotaWithoutLeakingIdentity() throws {
        let (connection, windows) = try normalize(payload())
        XCTAssertEqual(connection.status, "connected")
        XCTAssertEqual(connection.source, "oauth")
        XCTAssertEqual(connection.planContext, .organization)
        XCTAssertEqual(connection.accountKey?.count, 24)
        XCTAssertEqual(windows.first?.limitID, "codex:primary")
        XCTAssertEqual(windows.first?.remainingPercent, 80)
        let encoded = String(data: try JSONEncoder().encode(connection), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("PRIVATE"))
    }
    func testOnlyFirstAccountIsUsed() throws {
        var other = payload(); other["usage"] = ["identity": ["loginMethod": "Free"]]
        let (connection, windows) = try normalize([payload(), other])
        XCTAssertEqual(connection.planLabel, "Enterprise"); XCTAssertEqual(windows.count, 1)
    }
    func testInvalidAndBooleanCountersAreUnknown() throws {
        for value: Any in [true, -1, 101, "20"] {
            var row = payload(); var usage = row["usage"] as! [String: Any]
            usage["primary"] = ["usedPercent": value, "windowMinutes": 300, "resetsAt": "2026-10-08T12:00:00Z"]
            row["usage"] = usage
            XCTAssertTrue(try normalize(row).1.isEmpty)
        }
    }
    func testInvalidOrUnzonedDatesAreUnknown() throws {
        for date in ["2026-10-08T10:00:00", "invalid"] {
            var row = payload(); var usage = row["usage"] as! [String: Any]; usage["updatedAt"] = date; row["usage"] = usage
            XCTAssertTrue(try normalize(row).1.isEmpty)
        }
    }
    func testErrorPayloadCannotEstablishPaidPlan() throws {
        var row = payload(); row["error"] = "auth failed"
        let (connection, windows) = try normalize(row)
        XCTAssertEqual(connection.status, "unavailable"); XCTAssertNil(connection.planLabel); XCTAssertTrue(windows.isEmpty)
    }
    func testFalseErrorAndFractionalTimestampAreAccepted() throws {
        var row = payload(); row["error"] = false
        var usage = row["usage"] as! [String: Any]; usage["updatedAt"] = "2026-10-08T10:00:00.123Z"; row["usage"] = usage
        XCTAssertEqual(try normalize(row).1.count, 1)
    }
    func testAnonymousReadingsNeverAcquireAccountOwnership() throws {
        var row = payload(); var usage = row["usage"] as! [String: Any]; usage.removeValue(forKey: "identity"); row["usage"] = usage
        let (connection, windows) = try normalize(row)
        XCTAssertNil(connection.accountKey); XCTAssertNil(windows.first?.accountKey); XCTAssertNil(connection.planLabel)
    }
}
