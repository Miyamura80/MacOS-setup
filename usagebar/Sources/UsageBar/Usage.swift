import Foundation
import CoreFoundation

struct UsageWindow: Equatable, Sendable {
    let used: Double
    let resetsAt: Date?

    init(used: Double, resetsAt: Date?) throws {
        guard used.isFinite, (0...100).contains(used),
              resetsAt?.timeIntervalSince1970.isFinite ?? true else { throw UsageError.invalidResponse }
        self.used = used
        self.resetsAt = resetsAt
    }
}

enum Meter: String, CaseIterable, Identifiable {
    case codexWeek, claudeWeek, claudeSession
    var id: Self { self }
    var title: String { self == .codexWeek ? "Codex" : "Claude" }
    var period: String { self == .claudeSession ? "5 hours" : "Weekly" }
}

struct Reading {
    var window: UsageWindow?
    var fetchedAt: Date?
    var error: String?

    func isStale(at now: Date = Date()) -> Bool {
        guard let fetchedAt else { return true }
        return error != nil || now.timeIntervalSince(fetchedAt) > 600 ||
            (window?.resetsAt.map { $0 <= now } ?? false)
    }
}

enum UsageError: LocalizedError {
    case message(String)
    case invalidResponse
    case keychainAccessRequired
    case throttled(Date)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .invalidResponse: return "Usage data was not recognized. Open the provider’s usage page to check."
        case .keychainAccessRequired: return "Allow Keychain access to connect Claude Code’s sign-in."
        case .throttled(let date): return "Claude limited usage checks. Retrying after \(date.formatted(date: .omitted, time: .shortened))."
        }
    }
}

enum UsageParser {
    static func codex(_ data: Data) throws -> UsageWindow {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse
        }
        let result = root["result"] as? [String: Any] ?? root
        let bucket: [String: Any]
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            // A present multi-bucket result is authoritative, even if Codex is absent.
            guard let codex = buckets["codex"] as? [String: Any] else { throw noCodexLimits }
            bucket = codex
        } else {
            guard let legacy = result["rateLimits"] as? [String: Any],
                  legacy["limitId"] == nil || legacy["limitId"] is NSNull || legacy["limitId"] as? String == "codex" else {
                throw noCodexLimits
            }
            bucket = legacy
        }
        // Select by duration, never assume that secondary means weekly.
        let weekly = try ["primary", "secondary"].compactMap { bucket[$0] as? [String: Any] }
            .first { window in
                guard let duration = window["windowDurationMins"], !(duration is NSNull) else { return false }
                return try number(duration) == 10_080
            }
        guard let weekly else { throw UsageError.message("This Codex account did not report a weekly limit.") }
        return try UsageWindow(used: number(weekly["usedPercent"]), resetsAt: date(weekly["resetsAt"]))
    }

    private static var noCodexLimits: UsageError {
        .message("No Codex subscription limits. Sign in with ChatGPT using codex login.")
    }

    static func claude(_ data: Data) throws -> [Meter: UsageWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse
        }
        var windows: [Meter: UsageWindow] = [:]
        for (key, meter) in [("seven_day", Meter.claudeWeek), ("five_hour", Meter.claudeSession)] {
            guard let raw = root[key], !(raw is NSNull) else { continue }
            guard let value = raw as? [String: Any] else { throw UsageError.invalidResponse }
            windows[meter] = try UsageWindow(used: number(value["utilization"]), resetsAt: date(value["resets_at"]))
        }
        guard !windows.isEmpty else { throw UsageError.invalidResponse }
        return windows
    }

    static func number(_ value: Any?) throws -> Double {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { throw UsageError.invalidResponse }
        return value.doubleValue
    }

    static func date(_ value: Any?) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        if value is NSNumber { return Date(timeIntervalSince1970: try number(value)) }
        guard let text = value as? String else { throw UsageError.invalidResponse }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
            throw UsageError.invalidResponse
        }
        return date
    }
}
