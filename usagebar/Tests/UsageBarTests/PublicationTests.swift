import Foundation

extension UsageChecks {
    static func atomicPublication() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("UsageBar-publish-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let source = directory.appendingPathComponent("stage.app")
        let destination = directory.appendingPathComponent("published.app")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: source.appendingPathComponent("marker"))
        try BundlePublication.publish(source: source, destination: destination)
        try expect(!manager.fileExists(atPath: source.path), "First publication moves the staged directory")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("second".utf8).write(to: source.appendingPathComponent("marker"))
        try BundlePublication.publish(source: source, destination: destination)
        try expect(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8) == "second", "Atomically publish the replacement")
        try expect(try String(contentsOf: source.appendingPathComponent("marker"), encoding: .utf8) == "first", "Retain the previous app in staging until publication succeeds")
        try rejects { try BundlePublication.publish(source: directory.appendingPathComponent("missing.app"), destination: destination) }
        try expect(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8) == "second", "A failed replacement cannot remove the published app")
    }
}
