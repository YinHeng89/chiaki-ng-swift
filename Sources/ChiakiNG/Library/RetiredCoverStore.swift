import ChiakiModels
import Foundation

/// The on-disk cover cache earlier versions kept, removed once at launch now that covers live in memory.
enum RetiredCoverStore {
    /// Where earlier versions kept covers.
    static let directory = UserData.current.caches.appendingPathComponent("CloudArtwork", isDirectory: true)

    /// Removes the retired directory.
    ///
    /// - Parameter directory: The directory to remove.
    /// - Returns: `true` when a directory was there and was removed.
    @discardableResult static func remove(at directory: URL = directory) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return false
        }
        return (try? FileManager.default.removeItem(at: directory)) != nil
    }
}
