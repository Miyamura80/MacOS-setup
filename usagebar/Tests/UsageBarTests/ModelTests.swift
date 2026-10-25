import Foundation
import ServiceManagement

private actor RefreshFixture {
    private var continuation: CheckedContinuation<[Meter: UsageWindow], Error>?
    private var codexCalls = 0
    private var released = false
    func codex() throws -> UsageWindow {
        codexCalls += 1
        if codexCalls == 3 { throw UsageError.message("Test offline") }
        return try UsageWindow(used: Double(codexCalls), resetsAt: nil)
    }
    func blockedClaude() async throws -> [Meter: UsageWindow] {
        if released { return [:] }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func releaseClaude() { released = true; continuation?.resume(returning: [:]); continuation = nil }
}

extension UsageChecks {
    @MainActor
    static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !predicate() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure(description: "Model condition timed out") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    @MainActor
    static func independentRefreshes() async throws {
        let fixture = RefreshFixture()
        let model = AppModel(codexFetch: { try await fixture.codex() },
                             claudeFetch: { _ in try await fixture.blockedClaude() })
        model.refresh()
        try await waitUntil { !model.refreshingCodex && model.refreshingClaude }
        try expect(model.readings[.codexWeek]?.window?.used == 1, "Codex completes while Claude waits")
        model.refresh()
        try await waitUntil { !model.refreshingCodex }
        try expect(model.readings[.codexWeek]?.window?.used == 2, "A blocked Claude check cannot prevent another Codex refresh")
        model.refresh()
        try await waitUntil { !model.refreshingCodex }
        try expect(model.readings[.codexWeek]?.window?.used == 2, "Retain cached usage after failure")
        try expect(model.readings[.codexWeek]?.isStale() == true, "Mark retained data stale")
        await fixture.releaseClaude()
        try await waitUntil { !model.refreshingClaude }
    }

    @MainActor
    static func cooldownAndKeychain() async throws {
        let model = AppModel(codexFetch: { try UsageWindow(used: 0, resetsAt: nil) }, claudeFetch: { _ in
            throw UsageError.throttled(Date().addingTimeInterval(900))
        })
        model.refresh()
        try await waitUntil { !model.refreshing }
        try expect(model.claudeRetryAt != nil, "Record Claude cooldown")
        model.refreshClaude(allowKeychainPrompt: true)
        try expect(!model.refreshingClaude, "Manual and explicit-auth refreshes cannot bypass cooldown")
        let keychain = AppModel(codexFetch: { try UsageWindow(used: 0, resetsAt: nil) }, claudeFetch: { allowPrompt in
            if !allowPrompt { throw UsageError.keychainAccessRequired }
            return [.claudeWeek: try UsageWindow(used: 50, resetsAt: nil)]
        })
        keychain.refresh()
        try await waitUntil { !keychain.refreshing }
        try expect(keychain.claudeNeedsAccess, "Expose an explicit Keychain action after a non-interactive check")
        keychain.refreshClaude(allowKeychainPrompt: true)
        try await waitUntil { !keychain.refreshingClaude }
        try expect(!keychain.claudeNeedsAccess && keychain.readings[.claudeWeek]?.window?.used == 50, "Explicit access can recover the provider")
        try expect(keychain.readings[.claudeSession]?.window == nil, "A missing session window stays unavailable")
    }
}

@MainActor
private final class LoginFixture {
    var status = SMAppService.Status.requiresApproval
    var changes: [Bool] = []
    func change(_ enabled: Bool) { changes.append(enabled); status = enabled ? .enabled : .notRegistered }
}

extension UsageChecks {
    @MainActor
    static func loginState() throws {
        let fixture = LoginFixture()
        let model = AppModel(loginStatus: { fixture.status }, changeLogin: { fixture.change($0) })
        try expect(!model.loginEnabled && model.loginError != nil, "Expose pending System Settings approval")
        fixture.status = .enabled
        model.setLaunchAtLogin(true)
        try expect(fixture.changes.isEmpty, "A stale off-state must not unregister an approved service")
        try expect(model.loginEnabled && model.loginError == nil, "Re-read external approval")
        model.setLaunchAtLogin(false)
        try expect(fixture.changes == [false] && !model.loginEnabled, "Honor the requested disabled state")
        fixture.status = .enabled
        model.refreshLoginStatus()
        try expect(model.loginEnabled, "Refresh state after returning from System Settings")
    }
}
