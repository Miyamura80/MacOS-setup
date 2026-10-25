import AppKit
import SwiftUI

@main
struct UsageBarMain {
    @MainActor
    static func main() async {
        do { try await run() }
        catch {
            fputs("UsageBar: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.indices.contains(flag + 1) {
            _ = NSApplication.shared
            let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for provider in UsageProvider.allCases {
                guard provider.image?.isValid == true else { throw UsageError.message("Missing or invalid SVG: \(provider.title)") }
            }
            let model = AppModel(demo: true)
            for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let background = scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color.white
                let renderer = ImageRenderer(content: UsagePanel(model: model, renderingPreview: true)
                    .environment(\.colorScheme, scheme).background(background))
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    throw UsageError.message("Preview rendering failed")
                }
                try png.write(to: directory.appendingPathComponent("\(name).png"))
            }
            guard let tiff = TrayImage.make(readings: model.readings).tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                throw UsageError.message("Tray preview rendering failed")
            }
            try png.write(to: directory.appendingPathComponent("tray.png"))
            print("Rendered previews; both bundled SVG icons loaded successfully.")
            return
        }
        if CommandLine.arguments.contains("--check") {
            var failed = false
            do {
                let window = try await CodexProvider.fetch()
                print("Codex weekly: \(Int(window.used.rounded()))% used")
            } catch { print("Codex: \(error.localizedDescription)"); failed = true }
            do {
                let windows = try await ClaudeProvider.fetch()
                for meter in [Meter.claudeWeek, .claudeSession] {
                    if let window = windows[meter] { print("Claude \(meter.period): \(Int(window.used.rounded()))% used") }
                    else { print("Claude \(meter.period): not reported"); failed = true }
                }
            } catch { print("Claude: \(error.localizedDescription)"); failed = true }
            exit(failed ? 1 : 0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let model = AppModel(demo: CommandLine.arguments.contains("--demo"))
    private var wakeObserver: NSObjectProtocol?
    private var displayTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: 52)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: UsagePanel(model: model))
        model.onUpdate = { [weak self] in self?.updateTray() }
        updateTray()
        model.start()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTray() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.model.refresh() } }
        if CommandLine.arguments.contains("--preview") { togglePopover() }
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateTray() {
        let readings = model.readings
        item.button?.image = TrayImage.make(readings: readings)
        let description = Meter.allCases.map { meter in
            let reading = readings[meter]
            let value = reading?.window.map { "\(Int($0.used.rounded()))% used\(reading?.isStale() == true ? " (stale)" : "")" } ?? "unavailable"
            return "\(meter.title) \(meter.period): \(value)"
        }.joined(separator: "\n")
        item.button?.toolTip = "UsageBar\n" + description
        item.button?.setAccessibilityLabel("UsageBar. " + description)
    }
}

extension Meter {
    var nsColor: NSColor {
        switch self {
        case .codexWeek: return NSColor.systemMint
        case .claudeWeek: return NSColor.systemOrange
        case .claudeSession: return NSColor.systemBlue
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}

struct UsagePanel: View {
    @ObservedObject var model: AppModel
    var renderingPreview = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("usagebar").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Spacer()
                    if model.demo { Text("Preview").font(.caption).foregroundStyle(.secondary) }
                    if model.refreshing { ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 20) }
                    Group {
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain).help("Refresh usage").accessibilityLabel("Refresh usage")
                            .disabled(model.demo)
                    }
                }
                .padding(.bottom, 24)
                ForEach(UsageProvider.allCases) { provider in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            BrandIcon(provider: provider).accessibilityHidden(true)
                            Text(provider.title).font(.system(size: 13, weight: .semibold))
                        }
                        .accessibilityAddTraits(.isHeader)
                        ForEach(provider.meters) { meter in
                            UsageRow(meter: meter, reading: model.readings[meter] ?? Reading(),
                                     now: context.date, loading: provider == .codex ? model.refreshingCodex : model.refreshingClaude,
                                     showError: meter != .claudeSession ||
                                        model.readings[.claudeWeek]?.error != model.readings[.claudeSession]?.error)
                        }
                        if provider == .claude, model.claudeNeedsAccess {
                            Button("Allow Keychain Access…") { model.refreshClaude(allowKeychainPrompt: true) }
                                .controlSize(.small).disabled(model.refreshingClaude)
                        }
                    }
                    .padding(.bottom, 18)
                    if provider == .codex { Divider().padding(.bottom, 18) }
                }
                Divider()
                HStack {
                    Text(model.demo ? "Sample data" : "Percent used · checks every 5 min")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if renderingPreview {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                    } else {
                        Menu {
                            Toggle("Launch at Login", isOn: Binding(get: { model.loginEnabled }, set: { _ in model.toggleLogin() }))
                            Divider()
                            Button("Codex Usage…") { open("https://chatgpt.com/codex/settings/usage") }
                            Button("Claude Usage…") { open("https://claude.ai/settings/usage") }
                            Divider()
                            Button("Quit UsageBar") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).fixedSize().help("Options").accessibilityLabel("Options")
                    }
                }.padding(.top, 12)
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.orange).padding(.top, 10)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }

    private func open(_ address: String) { NSWorkspace.shared.open(URL(string: address)!) }
}

private struct UsageRow: View {
    let meter: Meter
    let reading: Reading
    let now: Date
    let loading: Bool
    let showError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(meter.period).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(reading.window.map { "\(Int($0.used.rounded()))%" } ?? "—")
                    .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(reading.isStale(at: now) ? Color.secondary : Color.primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    if let window = reading.window {
                        Capsule().fill(reading.isStale(at: now) ? Color.secondary : meter.color)
                            .frame(width: geometry.size.width * window.used / 100)
                    }
                }
            }
            .frame(height: 6)
            .accessibilityLabel("\(meter.title) \(meter.period) usage")
            .accessibilityValue(reading.window.map { "\(Int($0.used.rounded())) percent used" } ?? "Unavailable")
            if let error = reading.error, showError {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let window = reading.window {
                    if reading.isStale(at: now) { Text("Stale reading").foregroundStyle(.orange) }
                    else if let reset = window.resetsAt {
                        Text(reset <= now ? "Reset due · awaiting update" : "Resets \(reset.formatted(.relative(presentation: .named)))")
                            .help(reset.formatted(date: .complete, time: .shortened))
                    } else { Text("Reset time unavailable") }
                    Spacer()
                    if let fetched = reading.fetchedAt { Text(fetched, style: .relative).help("Last checked \(fetched.formatted())") }
                } else if reading.error == nil { Text(loading ? "Checking usage…" : "Waiting for usage") }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
