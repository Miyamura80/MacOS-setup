import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var readings: [Meter: Reading] = [:]
    @Published private(set) var refreshingCodex = false
    @Published private(set) var refreshingClaude = false
    @Published private(set) var claudeNeedsAccess = false
    @Published var loginError: String?
    @Published private(set) var loginEnabled = false
    @Published private(set) var claudeRetryAt: Date?
    var refreshing: Bool { refreshingCodex || refreshingClaude }
    let demo: Bool
    private var timer: Timer?
    private var started = false
    private let codexFetch: @Sendable () async throws -> UsageWindow
    private let claudeFetch: @Sendable (Bool) async throws -> [Meter: UsageWindow]
    private let loginStatus: () -> SMAppService.Status
    private let changeLogin: (Bool) throws -> Void
    var onUpdate: (() -> Void)?

    init(demo: Bool = false,
         codexFetch: @escaping @Sendable () async throws -> UsageWindow = { try await CodexProvider.fetch() },
         claudeFetch: @escaping @Sendable (Bool) async throws -> [Meter: UsageWindow] = { try await ClaudeProvider.fetch(allowKeychainPrompt: $0) },
         loginStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         changeLogin: @escaping (Bool) throws -> Void = {
             if $0 { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
         }) {
        self.demo = demo
        self.codexFetch = codexFetch
        self.claudeFetch = claudeFetch
        self.loginStatus = loginStatus
        self.changeLogin = changeLogin
        refreshLoginStatus()
        if demo {
            for (meter, value) in [(Meter.codexWeek, 38.0), (.claudeWeek, 64.0), (.claudeSession, 21.0)] {
                readings[meter] = Reading(window: try? UsageWindow(used: value,
                    resetsAt: Date().addingTimeInterval(meter == .claudeSession ? 8_100 : 259_200)), fetchedAt: Date())
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        guard !demo else { onUpdate?(); return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !demo else { return }
        refreshCodex()
        refreshClaude()
    }

    private func refreshCodex() {
        guard !refreshingCodex else { return }
        refreshingCodex = true
        Task {
            defer { refreshingCodex = false; onUpdate?() }
            do { set(.codexWeek, window: try await codexFetch()) }
            catch { fail(.codexWeek, error: error) }
        }
    }

    func refreshClaude(allowKeychainPrompt: Bool = false) {
        guard !demo, !refreshingClaude, claudeRetryAt.map({ $0 <= Date() }) ?? true else { return }
        refreshingClaude = true
        Task {
            defer { refreshingClaude = false; onUpdate?() }
            do {
                let windows = try await claudeFetch(allowKeychainPrompt)
                claudeRetryAt = nil
                claudeNeedsAccess = false
                for meter in [Meter.claudeWeek, .claudeSession] {
                    if let window = windows[meter] { set(meter, window: window) }
                    else { readings[meter] = Reading(error: "This Claude account did not report this usage window.") }
                }
            } catch {
                claudeNeedsAccess = false
                if case UsageError.throttled(let date) = error { claudeRetryAt = date }
                if case UsageError.keychainAccessRequired = error { claudeNeedsAccess = true }
                fail(.claudeWeek, error: error)
                fail(.claudeSession, error: error)
            }
        }
    }

    private func set(_ meter: Meter, window: UsageWindow) {
        readings[meter] = Reading(window: window, fetchedAt: Date())
    }

    private func fail(_ meter: Meter, error: Error) {
        var reading = readings[meter] ?? Reading()
        reading.error = error.localizedDescription
        readings[meter] = reading
    }

    func refreshLoginStatus() {
        let status = loginStatus()
        loginEnabled = status == .enabled
        loginError = status == .requiresApproval
            ? "Allow UsageBar in System Settings → General → Login Items." : nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let status = loginStatus()
            if enabled && status != .enabled && status != .requiresApproval { try changeLogin(true) }
            if !enabled && status != .notRegistered { try changeLogin(false) }
            refreshLoginStatus()
        } catch {
            loginEnabled = loginStatus() == .enabled
            loginError = error.localizedDescription
        }
    }
}
