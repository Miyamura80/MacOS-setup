import Foundation

extension UsageChecks {
    static func resetTimeFormatting() throws {
        let now = try UsageParser.date("2026-10-25T12:00:00Z")!
        let cases: [(TimeInterval, String)] = [
            (7 * 86_400, "Resets in 7d"),
            (7 * 86_400 - 1, "Resets in 6d 23h"),
            (2 * 86_400 + 3 * 3_600, "Resets in 2d 3h"),
            (3_600, "Resets in 1h"),
            (8_100, "Resets in 2h 15m"),
            (60, "Resets in 1m"),
            (59, "Resets in <1m"),
            (0, "Reset due · awaiting update"),
            (-1, "Reset due · awaiting update")
        ]
        for (offset, expected) in cases {
            try expect(UsageTime.resetCountdown(now.addingTimeInterval(offset), now: now) == expected,
                       "Countdown boundary at \(offset) seconds")
        }
        let reset = try UsageParser.date("2026-10-26T05:00:00Z")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let utc = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_GB")
        let localText = UsageTime.resetTimestamp(reset, locale: locale, timeZone: tokyo)
        let utcText = UsageTime.resetTimestamp(reset, locale: locale, timeZone: utc)
        try expect(localText.contains("14:00") && localText.contains("26") && localText.contains("Mon"),
                   "Show the reset clock time and date in the requested local zone")
        try expect(utcText.contains("05:00"), "Do not reinterpret UTC timestamps as local clock times")
        let afterMidnight = try UsageParser.date("2026-10-25T15:30:00Z")!
        let midnightText = UsageTime.resetTimestamp(afterMidnight, locale: locale, timeZone: tokyo)
        try expect(midnightText.contains("26") && midnightText.contains("00:30"), "Carry the date across local midnight")
        // A DST fall-back must leave the elapsed countdown correct, regardless of clock labels.
        let dstBefore = try UsageParser.date("2026-11-01T05:30:00Z")!
        let dstAfter = try UsageParser.date("2026-11-01T06:30:00Z")!
        try expect(UsageTime.resetCountdown(dstAfter, now: dstBefore) == "Resets in 1h", "Use elapsed time across DST")
        try expect(UsageTime.details(reset: reset, fetched: now).contains("Last checked:"),
                   "Label refresh age separately in the tooltip")
    }
}
