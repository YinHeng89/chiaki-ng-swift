import ChiakiModels
import PlatformUI

/// Reads the device's accessibility preferences that PlayStation accessibility follows until changed.
@MainActor
public enum PlayStationAccessibilitySystemDefaults {
    /// The device's screen reader, text size, bold text and contrast preferences now.
    public static var current: PlayStationAccessibilityDefaults {
        PlayStationAccessibilityDefaults(
            screenReader: PlatformAccessibility.screenReaderRunning,
            textSize: PlatformAccessibility.preferredCloudTextSize,
            boldText: PlatformAccessibility.prefersBoldText,
            higherContrast: PlatformAccessibility.prefersHigherContrast
        )
    }
}
