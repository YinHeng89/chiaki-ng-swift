import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Opens URLs with the system on either platform.
@MainActor
public enum PlatformWorkspace {
    /// Opens a URL in the app the system chooses for it.
    ///
    /// - Parameter url: The URL to open.
    /// - Returns: Whether the system accepted the URL; on iOS it opens it asynchronously, so this is always
    ///   true.
    @discardableResult
    public static func open(_ url: URL) -> Bool {
        #if canImport(AppKit)
            return NSWorkspace.shared.open(url)
        #else
            UIApplication.shared.open(url)
            return true
        #endif
    }
}
