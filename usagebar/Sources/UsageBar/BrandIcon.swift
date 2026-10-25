import AppKit
import SwiftUI

enum UsageProvider: String, CaseIterable, Identifiable {
    case codex, claude
    var id: Self { self }
    var title: String { self == .codex ? "Codex" : "Claude" }
    var meters: [Meter] { self == .codex ? [.codexWeek] : [.claudeWeek, .claudeSession] }

    var image: NSImage? { Self.images[self] }
    // SwiftPM 6.1 and 6.4 generate different Bundle.module lookups. A packaged app
    // always owns its resource bundle; command-line builds keep it beside the executable.
    private static let resourceBundle: Bundle? = {
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            guard let base else { continue }
            if let bundle = Bundle(url: base.appendingPathComponent("UsageBar_UsageBar.bundle")) { return bundle }
        }
        return nil
    }()
    private static let images: [Self: NSImage] = Dictionary(uniqueKeysWithValues: allCases.compactMap { provider in
        guard let url = resourceBundle?.url(forResource: provider == .codex ? "chatgpt" : "claude", withExtension: "svg", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = provider == .codex
        return (provider, image)
    })
}

struct BrandIcon: View {
    let provider: UsageProvider

    var body: some View {
        Group {
            if let image = provider.image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(provider == .codex ? .template : .original)
                    .interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "chart.bar.fill").resizable().scaledToFit()
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(provider.title)
    }
}

enum TrayImage {
    static func make(readings: [Meter: Reading]) -> NSImage {
        let image = NSImage(size: NSSize(width: 42, height: 20), flipped: false) { _ in
            for provider in UsageProvider.allCases {
                let iconRect = NSRect(x: 0, y: provider == .codex ? 10 : 0, width: 10, height: 10)
                provider.image?.draw(in: iconRect)
                if provider == .codex {
                    // Tint the ChatGPT SVG to match the current menu bar appearance.
                    NSColor.labelColor.setFill()
                    iconRect.fill(using: .sourceAtop)
                }
                for (index, meter) in provider.meters.enumerated() {
                    let y: CGFloat = provider == .codex ? 16 : (index == 0 ? 7.5 : 2)
                    let track = NSRect(x: 14, y: y, width: 28, height: 3)
                    NSColor.labelColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
                    let reading = readings[meter]
                    if let window = reading?.window {
                        let stale = reading?.isStale() ?? true
                        (stale ? NSColor.secondaryLabelColor : meter.nsColor).setFill()
                        if window.used > 0 {
                            NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY,
                                width: max(1, track.width * window.used / 100), height: 3),
                                xRadius: 1.5, yRadius: 1.5).fill()
                        }
                        if stale {
                            NSColor.labelColor.setFill()
                            NSBezierPath(ovalIn: NSRect(x: track.maxX - 3, y: track.minY, width: 3, height: 3)).fill()
                        }
                    } else {
                        NSColor.secondaryLabelColor.setFill()
                        NSBezierPath(roundedRect: NSRect(x: track.midX - 3, y: track.minY, width: 6, height: 3),
                                     xRadius: 1.5, yRadius: 1.5).fill()
                    }
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
