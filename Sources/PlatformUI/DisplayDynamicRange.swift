#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Reports whether the display showing the app can present extended dynamic range content.
public enum DisplayDynamicRange {
    /// Whether the key, main or primary screen offers headroom above standard dynamic range.
    @MainActor public static var supportsHDR: Bool {
        #if os(macOS)
            let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
            return (screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1
        #else
            return UIScreen.main.potentialEDRHeadroom > 1
        #endif
    }
}
