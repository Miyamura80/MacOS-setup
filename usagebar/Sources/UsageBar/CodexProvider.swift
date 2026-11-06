import Foundation
import Darwin

enum CodexProvider {
    static func fetch() async throws -> UsageWindow {
        try await Task.detached(priority: .utility) { try readLimits() }.value
    }

    private static func executable() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
                          "/Applications/Codex.app/Contents/Resources/codex",
                          "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UsageError.message("Install Codex CLI, then run codex login in Terminal.")
        }
        return URL(fileURLWithPath: path)
    }

    // An explicit executable and short timeout let tests use local RPC fixtures, never real accounts.
    static func readLimits(executableURL: URL? = nil, timeout: TimeInterval = 25) throws -> UsageWindow {
        let process = Process()
        process.executableURL = try executableURL ?? executable()
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A CLI that exits during the handshake must produce a write error, not kill UsageBar.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw UsageError.message("Could not prepare the Codex connection.")
        }
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
                let stopDeadline = ProcessInfo.processInfo.systemUptime + 1
                while process.isRunning, ProcessInfo.processInfo.systemUptime < stopDeadline { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            // Reap the child before returning, including when this is a short-lived --check process.
            process.waitUntilExit()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "usagebar", "title": "UsageBar", "version": "1.0.0"]
        ]])
        var buffer = Data()
        var received = 0
        var initialized = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; break }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            received += count
            guard received <= 2_000_000 else { throw UsageError.invalidResponse }
            buffer.append(contentsOf: bytes.prefix(count))
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["method"] == nil, let id = object["id"] as? Int,
                      (!initialized && id == 1) || (initialized && id == 2) else { continue }
                if object["error"] != nil {
                    throw UsageError.message("Codex could not read usage. Run codex login in Terminal, then refresh.")
                }
                guard object["result"] is [String: Any] else { throw UsageError.invalidResponse }
                if id == 1 {
                    initialized = true
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else {
                    return try UsageParser.codex(line)
                }
            }
        }
        throw UsageError.message("Codex usage check timed out or stopped. Check the Codex CLI connection, then refresh.")
    }
}
