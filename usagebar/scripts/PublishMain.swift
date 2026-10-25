import Foundation

@main
struct PublishMain {
    static func main() {
        guard CommandLine.arguments.count == 3 else { fputs("Usage: publish SOURCE DESTINATION\n", stderr); exit(64) }
        do {
            try BundlePublication.publish(source: URL(fileURLWithPath: CommandLine.arguments[1]),
                                          destination: URL(fileURLWithPath: CommandLine.arguments[2]))
        } catch { fputs("Could not publish app: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
