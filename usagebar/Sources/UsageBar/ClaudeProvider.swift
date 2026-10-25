import Foundation
import Security
import LocalAuthentication

// Never forward subscription credentials to redirects or persist them in app preferences.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum ClaudeProvider {
    static func fetch(allowKeychainPrompt: Bool = false) async throws -> [Meter: UsageWindow] {
        let token = try await Task.detached(priority: .utility) {
            try accessToken(allowKeychainPrompt: allowKeychainPrompt)
        }.value
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await fetch(token: token, session: session)
    }

    // Injectable transport keeps the regression suite independent of accounts and network access.
    static func fetch(token: String, session: URLSession, now: Date = Date()) async throws -> [Meter: UsageWindow] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        switch response.statusCode {
        case 200: return try UsageParser.claude(data)
        case 401, 403:
            throw UsageError.message("Claude sign-in needs attention. Open Claude Code and run /login, then refresh.")
        case 429:
            throw UsageError.throttled(retryDate(response.value(forHTTPHeaderField: "Retry-After"), now: now))
        default: throw UsageError.message("Claude usage is unavailable (HTTP \(response.statusCode)). Try again later.")
        }
    }

    static func retryDate(_ header: String?, now: Date) -> Date {
        let earliest = now.addingTimeInterval(900)
        guard let header else { return earliest }
        if let seconds = Double(header) {
            guard seconds.isFinite, seconds >= 0, seconds <= 30 * 86_400 else { return earliest }
            return max(earliest, now.addingTimeInterval(seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return max(earliest, formatter.date(from: header) ?? earliest)
    }

    static func credentialDirectory(environment: [String: String], home: URL) -> URL {
        guard let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty else {
            return home.appendingPathComponent(".claude").standardizedFileURL
        }
        return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath).standardizedFileURL
    }

    private static func accessToken(allowKeychainPrompt: Bool) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = credentialDirectory(environment: ProcessInfo.processInfo.environment, home: home)
        let isDefaultProfile = directory == home.appendingPathComponent(".claude").standardizedFileURL
        var credentialData: Data?
        // Custom profiles must never silently use the default profile's Keychain login.
        if isDefaultProfile {
            let context = LAContext()
            context.interactionNotAllowed = !allowKeychainPrompt
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Claude Code-credentials",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess: credentialData = result as? Data
            case errSecItemNotFound: break
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
                throw UsageError.keychainAccessRequired
            default: throw UsageError.message("Claude’s Keychain sign-in is unavailable (\(status)). Open Keychain Access to check it.")
            }
        }
        if credentialData == nil {
            credentialData = try? Data(contentsOf: directory.appendingPathComponent(".credentials.json"))
        }
        guard let data = credentialData else {
            throw UsageError.message(isDefaultProfile
                ? "Sign in to Claude Code with /login to connect your subscription."
                : "This Claude profile has no credentials file. Custom Keychain profiles are not supported; use the default Claude Code profile.")
        }
        return try token(from: data)
    }

    static func token(from data: Data, now: Date = Date()) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError.message("No Claude subscription sign-in. Open Claude Code and run /login.")
        }
        // Claude Code owns refresh-token rotation; never mutate its Keychain entry.
        if let expiry = oauth["expiresAt"] {
            guard let expiry = try? UsageParser.number(expiry), expiry / 1000 > now.timeIntervalSince1970 else {
                throw UsageError.message("Claude sign-in expired. Open Claude Code to renew it, then refresh.")
            }
        }
        return token
    }
}
