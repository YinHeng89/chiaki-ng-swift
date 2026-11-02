import Foundation
import Synchronization

/// Keeps a folder the user chose, such as the log or capture folder, reachable after the app relaunches.
///
/// A sandboxed app may reach a folder outside its container again after a relaunch only through a
/// security-scoped bookmark made while the user's choice still grants access. ``bookmark(for:)`` makes one when
/// the folder is chosen; ``open(_:bookmark:)`` resolves it and keeps the access for the rest of the process, so
/// every later writer can use the folder's path as it is. Outside the sandbox, and for folders the app can
/// already reach, nothing changes: the path works without a bookmark.
public enum FolderAccess {
    private static let opened = Mutex<Set<String>>([])

    /// Makes a bookmark for a folder the user just chose.
    ///
    /// - Parameter folder: The chosen folder.
    /// - Returns: The bookmark, or `nil` on platforms without security-scoped bookmarks or when the system
    ///   refuses one.
    public static func bookmark(for folder: URL) -> Data? {
        #if os(macOS)
            try? folder.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
            )
        #else
            nil
        #endif
    }

    /// Opens the access a folder's bookmark grants and keeps it until the process ends.
    ///
    /// Opening the same folder again does nothing. A bookmark for a folder that has since moved still opens
    /// access to it, but writers keep using `path`, so they reach it only once the user chooses it again.
    ///
    /// - Parameters:
    ///   - path: The folder's absolute path, as saved with the bookmark.
    ///   - bookmark: The bookmark saved when the folder was chosen, or `nil` when there is none.
    /// - Returns: Whether the bookmark granted access to `path`.
    @discardableResult
    public static func open(_ path: String, bookmark: Data?) -> Bool {
        #if os(macOS)
            guard let bookmark else {
                return false
            }
            return opened.withLock { paths in
                if paths.contains(path) {
                    return true
                }
                var stale = false
                guard let folder = try? URL(
                    resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ), folder.startAccessingSecurityScopedResource() else {
                    return false
                }
                paths.insert(path)
                return folder.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
            }
        #else
            return false
        #endif
    }
}
