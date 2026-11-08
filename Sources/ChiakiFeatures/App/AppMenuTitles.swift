import Foundation

/// The titles of the app's menu bar commands.
public enum AppMenuTitles {
    /// Brings the main window forward.
    public static let showMainWindow: LocalizedStringResource = .appMenuShowMainWindow

    /// Opens the stream controls.
    public static let streamControls: LocalizedStringResource = .appMenuStreamControls

    /// Shows the detailed stream diagnostics.
    public static let streamDiagnosticsDetail: LocalizedStringResource = .appMenuStreamDiagnosticsDetail

    /// Shows the glass stream diagnostics.
    public static let streamDiagnosticsGlass: LocalizedStringResource = .appMenuStreamDiagnosticsGlass

    /// Opens the live developer log.
    public static let liveDeveloperLog: LocalizedStringResource = .appMenuLiveDeveloperLog

    /// Shows the virtual touchpad.
    public static let virtualTouchpad: LocalizedStringResource = .appMenuVirtualTouchpad

    /// The developer menu.
    public static let developer: LocalizedStringResource = .appDeveloperMenu

    /// Shows the sample PS5.
    public static let showSamplePS5: LocalizedStringResource = .appDeveloperShowSamplePs5

    /// Shows the sample PS4.
    public static let showSamplePS4: LocalizedStringResource = .appDeveloperShowSamplePs4

    /// Shows both sample consoles.
    public static let showBothSamples: LocalizedStringResource = .appDeveloperShowBothSamples

    /// Hides the sample consoles.
    public static let hideSamples: LocalizedStringResource = .appDeveloperHideSamples
}
