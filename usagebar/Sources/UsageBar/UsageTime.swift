import Foundation

enum UsageTime {
    static func resetCountdown(_ reset: Date, now: Date) -> String {
        let remaining = reset.timeIntervalSince(now)
        guard remaining.isFinite, remaining < Double(Int.max) else { return "Reset time unavailable" }
        guard remaining > 0 else { return "Reset due · awaiting update" }
        guard remaining >= 60 else { return "Resets in <1m" }
        let minutes = Int(remaining / 60)
        let days = minutes / 1_440
        let hours = minutes / 60 % 24
        if days > 0 { return "Resets in \(days)d" + (hours > 0 ? " \(hours)h" : "") }
        let remainder = minutes % 60
        if hours > 0 { return "Resets in \(hours)h" + (remainder > 0 ? " \(remainder)m" : "") }
        return "Resets in \(minutes)m"
    }

    static func resetTimestamp(_ reset: Date, locale: Locale = .autoupdatingCurrent,
                               timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let format = Date.FormatStyle(locale: locale, timeZone: timeZone)
            .weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        return reset.formatted(format)
    }

    static func details(reset: Date?, fetched: Date?) -> String {
        var lines: [String] = []
        if let reset {
            let zone = TimeZone.autoupdatingCurrent.abbreviation(for: reset) ?? TimeZone.autoupdatingCurrent.identifier
            lines.append("Reset: \(reset.formatted(date: .complete, time: .shortened)) (\(zone))")
        }
        if let fetched { lines.append("Last checked: \(fetched.formatted(date: .complete, time: .shortened))") }
        return lines.joined(separator: "\n")
    }
}
