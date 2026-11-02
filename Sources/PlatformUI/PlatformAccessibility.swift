import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Reads the system accessibility preferences a stream passes on to the console, on either platform.
@MainActor
public enum PlatformAccessibility {
    /// Whether VoiceOver is running.
    public static var screenReaderRunning: Bool {
        #if canImport(AppKit)
            NSWorkspace.shared.isVoiceOverEnabled
        #else
            UIAccessibility.isVoiceOverRunning
        #endif
    }

    /// Whether the user asked for higher contrast.
    public static var prefersHigherContrast: Bool {
        #if canImport(AppKit)
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #else
            UIAccessibility.isDarkerSystemColorsEnabled
        #endif
    }

    /// Whether the user asked for bold text; macOS has no such preference.
    public static var prefersBoldText: Bool {
        #if canImport(AppKit)
            false
        #else
            UIAccessibility.isBoldTextEnabled
        #endif
    }

    /// The PlayStation text size matching the preferred text size, from -1 (small) to 2 (very large); macOS has
    /// no preferred text size, so it is standard there.
    public static var preferredCloudTextSize: Int {
        #if canImport(AppKit)
            0
        #else
            switch UIApplication.shared.preferredContentSizeCategory {
            case .extraSmall, .small:
                -1
            case .medium, .large:
                0
            case .extraLarge, .extraExtraLarge:
                1
            default:
                2
            }
        #endif
    }
}
