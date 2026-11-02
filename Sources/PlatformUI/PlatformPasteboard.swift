#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Copies text to and reads text from the system pasteboard on either platform.
@MainActor
public enum PlatformPasteboard {
    /// Replaces the pasteboard contents with a string.
    ///
    /// - Parameter string: The text to copy.
    public static func copy(_ string: String) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }

    /// The text on the pasteboard.
    ///
    /// - Returns: The pasteboard's string, or `nil` when it holds none.
    public static func string() -> String? {
        #if canImport(AppKit)
            NSPasteboard.general.string(forType: .string)
        #else
            UIPasteboard.general.string
        #endif
    }

    /// Replaces the pasteboard contents with a string that clipboard managers are asked not to record.
    ///
    /// - Parameter string: The secret text to copy.
    public static func copyConcealed(_ string: String) {
        #if canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
            pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        #else
            UIPasteboard.general.setItems(
                [["public.utf8-plain-text": string]],
                options: [.localOnly: true]
            )
        #endif
    }
}
