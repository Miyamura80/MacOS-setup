import Foundation

// Foundation-only checks run on Command Line Tools, without an Xcode/XCTest dependency.
@main
struct UsageChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String, line: Int = #line) throws {
        if try !condition() { throw Failure(description: "Line \(line): \(message)") }
    }

    static func rejects(_ action: () throws -> Void) throws {
        do { try action() }
        catch { return }
        throw Failure(description: "Expected invalid data to be rejected")
    }

    @MainActor
    static func main() async throws {
        try codexBucketSelection()
        try codexLegacyAndMissingWeek()
        try claudeWindows()
        try invalidData()
        try staleReadings()
        try strictDecoding()
        try credentials()
        try await claudeTransport()
        try codexTransport()
        try await independentRefreshes()
        try await cooldownAndKeychain()
        try loginState()
        try atomicPublication()
        try resetTimeFormatting()
        print("Passed 14 regression groups (providers, model state, bundle publication, and reset-time formatting).")
    }

    static func codexBucketSelection() throws {
        let payload = Data(#"{"rateLimits":{"secondary":{"usedPercent":99,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":{"usedPercent":8,"windowDurationMins":300}},"other":{"secondary":{"usedPercent":90,"windowDurationMins":10080}}}}"#.utf8)
        let window = try UsageParser.codex(payload)
        try expect(window.used == 42, "Choose the Codex bucket and weekly duration")
        try expect(window.resetsAt == Date(timeIntervalSince1970: 1_800_000_000), "Parse Unix reset date")
    }

    static func codexLegacyAndMissingWeek() throws {
        let payload = Data(#"{"id":2,"result":{"rateLimits":{"secondary":{"usedPercent":0,"windowDurationMins":10080}}}}"#.utf8)
        try expect(try UsageParser.codex(payload).used == 0, "Zero is valid usage")
        try rejects { _ = try UsageParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":3,"windowDurationMins":300}}}"#.utf8)) }
    }

    static func claudeWindows() throws {
        let windows = try UsageParser.claude(Data(#"{"five_hour":{"utilization":21.5,"resets_at":"2026-10-25T12:30:00.000Z"},"seven_day":null}"#.utf8))
        try expect(windows[.claudeSession]?.used == 21.5, "Read fractional Claude usage")
        try expect(windows[.claudeSession]?.resetsAt != nil, "Parse fractional ISO reset date")
        try expect(windows[.claudeWeek] == nil, "Missing usage must not be zero")
        let both = try UsageParser.claude(Data(#"{"five_hour":{"utilization":0},"seven_day":{"utilization":100,"resets_at":"2026-10-28T10:00:00Z"}}"#.utf8))
        try expect(both[.claudeWeek]?.used == 100, "Read full weekly usage")
        try expect(both[.claudeWeek]?.resetsAt != nil, "Parse whole-second ISO date")
    }

    static func invalidData() throws {
        for payload in [#"{}"#, #"{"five_hour":{"utilization":101}}"#, #"{"seven_day":{"utilization":-1}}"#, #"{"five_hour":{"utilization":"30"}}"#] {
            try rejects { _ = try UsageParser.claude(Data(payload.utf8)) }
        }
        try rejects { _ = try UsageWindow(used: .nan, resetsAt: nil) }
    }

    static func staleReadings() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = Reading(window: try UsageWindow(used: 0, resetsAt: now.addingTimeInterval(60)), fetchedAt: now)
        try expect(!fresh.isStale(at: now), "A fresh reading is current")
        try expect(fresh.isStale(at: now.addingTimeInterval(61)), "Do not show pre-reset usage as current")
        var failed = fresh
        failed.error = "Offline"
        try expect(failed.isStale(at: now), "Failed refresh marks cached data stale")
        try expect(Reading().isStale(at: now), "Unknown reading is stale")
        let old = Reading(window: try UsageWindow(used: 10, resetsAt: nil), fetchedAt: now.addingTimeInterval(-601))
        try expect(old.isStale(at: now), "Expire old readings")
    }
}
