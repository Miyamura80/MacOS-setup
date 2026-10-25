import Foundation
import Darwin

// Fake transport: all credentials are test literals; no requests leave the process.
final class MockUsageProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension UsageChecks {
    static func strictDecoding() throws {
        for payload in [
            #"{"five_hour":{"utilization":true}}"#,
            #"{"five_hour":{"utilization":1,"resets_at":true}}"#,
            #"{"five_hour":{"utilization":1,"resets_at":"bad date"}}"#,
            #"{"five_hour":"not a window"}"#
        ] { try rejects { _ = try UsageParser.claude(Data(payload.utf8)) } }
        let wrongBucket = Data(#"{"rateLimitsByLimitId":{"other":{}},"rateLimits":{"secondary":{"usedPercent":50,"windowDurationMins":10080}}}"#.utf8)
        try rejects { _ = try UsageParser.codex(wrongBucket) }
        let wrongLegacy = Data(#"{"rateLimits":{"limitId":"other","secondary":{"usedPercent":50,"windowDurationMins":10080}}}"#.utf8)
        try rejects { _ = try UsageParser.codex(wrongLegacy) }
        let nullDuration = Data(#"{"rateLimits":{"primary":{"windowDurationMins":null},"secondary":{"usedPercent":5,"windowDurationMins":10080}}}"#.utf8)
        try expect(try UsageParser.codex(nullDuration).used == 5, "An unreported primary duration cannot hide a valid weekly window")
    }

    static func credentials() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = Data(#"{"claudeAiOauth":{"accessToken":"test-only","expiresAt":1800001000000}}"#.utf8)
        try expect(try ClaudeProvider.token(from: valid, now: now) == "test-only", "Read a non-expired test token")
        for payload in [
            #"{"claudeAiOauth":{"accessToken":"test-only","expiresAt":1700000000000}}"#,
            #"{"claudeAiOauth":{"accessToken":"test-only","expiresAt":true}}"#,
            #"{"claudeAiOauth":{"accessToken":" "}}"#,
            #"{"accessToken":"test-only"}"#
        ] { try rejects { _ = try ClaudeProvider.token(from: Data(payload.utf8), now: now) } }
        let home = URL(fileURLWithPath: "/test-home")
        try expect(ClaudeProvider.credentialDirectory(environment: [:], home: home).path == "/test-home/.claude", "Default credentials directory")
        try expect(ClaudeProvider.credentialDirectory(environment: ["CLAUDE_CONFIG_DIR": "/other-profile"], home: home).path == "/other-profile", "Keep custom profiles isolated")
    }

    static func claudeTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockUsageProtocol.self]
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel(); MockUsageProtocol.handler = nil }
        MockUsageProtocol.handler = { request in
            try expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage", "Only send credentials to Anthropic's usage endpoint")
            try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only", "Send the test access token")
            try expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20", "Send the required beta header")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"five_hour":{"utilization":10},"seven_day":{"utilization":20}}"#.utf8))
        }
        let windows = try await ClaudeProvider.fetch(token: "test-only", session: session)
        try expect(windows[.claudeWeek]?.used == 20, "Decode the HTTP response")
        for status in [401, 403, 429, 500, 302] {
            MockUsageProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "3600"])!, Data())
            }
            let now = Date()
            do {
                _ = try await ClaudeProvider.fetch(token: "test-only", session: session, now: now)
                throw Failure(description: "Expected HTTP \(status) to fail")
            } catch let failure as Failure { throw failure }
            catch {
                if status == 429 {
                    guard case UsageError.throttled(let retry) = error else { throw error }
                    try expect(retry == now.addingTimeInterval(3600), "Honor Retry-After")
                }
            }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for header in [nil, "0", "-1", "NaN", "Infinity", "invalid"] as [String?] {
            try expect(ClaudeProvider.retryDate(header, now: now) == now.addingTimeInterval(900), "Bound invalid and zero Retry-After values")
        }
        try expect(ClaudeProvider.retryDate("Fri, 15 Jan 2027 09:00:00 GMT", now: now) > now.addingTimeInterval(900), "Accept HTTP-date Retry-After")
        let redirect = HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var refused = false
        NoRedirects().urlSession(session, task: session.dataTask(with: URL(string: "https://api.anthropic.com")!),
            willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: URL(string: "https://example.invalid")!)) {
                refused = $0 == nil
            }
        try expect(refused, "Refuse redirects before any credentials can be forwarded")
    }

    static func codexTransport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBar-RPC-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("codex-fixture")
        func fixture(_ body: String) throws {
            try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        }
        try fixture(#"""
        IFS= read -r first
        case "$first" in *initialize*) ;; *) exit 2 ;; esac
        printf '%s\n' '{"id":99,"error":{"message":"unrelated"}}'
        printf '%s' '{"id":1,'
        /bin/sleep 0.02
        printf '%s\n' '"result":{}}'
        IFS= read -r ack
        case "$ack" in *initialized*) ;; *) exit 3 ;; esac
        IFS= read -r request
        case "$request" in *rateLimits*) ;; *) exit 4 ;; esac
        case "$request" in *params*) exit 5 ;; esac
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"secondary":{"usedPercent":37,"windowDurationMins":10080}}}}'
        exec /bin/sleep 30
        """#)
        try expect(try CodexProvider.readLimits(executableURL: script, timeout: 2).used == 37, "RPC handshake, fragmented lines, unrelated IDs, and decoding")
        // Close the input pipe before replying, forcing the client's next write to encounter EPIPE.
        for _ in 0..<3 {
            try fixture(#"""
            IFS= read -r first
            exec 0<&-
            printf '%s\n' '{"id":1,"result":{}}'
            exit 0
            """#)
            try rejects { _ = try CodexProvider.readLimits(executableURL: script, timeout: 1) }
        }
        try fixture("exit 0\n")
        try rejects { _ = try CodexProvider.readLimits(executableURL: script, timeout: 1) }
        try fixture(#"""
        IFS= read -r first
        printf '%s\n' '{"id":1,"result":[]}'
        """#)
        try rejects { _ = try CodexProvider.readLimits(executableURL: script, timeout: 1) }
        try fixture("exec /usr/bin/head -c 2000001 /dev/zero\n")
        try rejects { _ = try CodexProvider.readLimits(executableURL: script, timeout: 2) }
        try fixture(#"""
        echo $$ > "${0%/*}/pid"
        trap '' TERM
        exec /bin/sleep 30
        """#)
        let start = ProcessInfo.processInfo.systemUptime
        try rejects { _ = try CodexProvider.readLimits(executableURL: script, timeout: 2) }
        try expect(ProcessInfo.processInfo.systemUptime - start < 6, "Bound a hung subprocess including forced termination")
        let pidText = try String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)
        guard let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw Failure(description: "Fixture PID missing") }
        try expect(kill(pid, 0) == -1 && errno == ESRCH, "Reap a child that ignores SIGTERM")
    }
}
