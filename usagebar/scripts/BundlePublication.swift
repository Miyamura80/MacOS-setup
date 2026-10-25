import Foundation
import Darwin

// Both paths live on the build volume. Swapping directory entries preserves the published
// app throughout replacement, and leaves the old bundle at the staging path for cleanup.
enum BundlePublication {
    static func publish(source: URL, destination: URL) throws {
        let exists = FileManager.default.fileExists(atPath: destination.path)
        let result = exists
            ? renamex_np(source.path, destination.path, UInt32(RENAME_SWAP))
            : rename(source.path, destination.path)
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination.path])
        }
    }
}
