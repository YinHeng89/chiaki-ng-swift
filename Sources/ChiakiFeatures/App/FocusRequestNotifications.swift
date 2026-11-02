import Foundation

extension Notification.Name {
    /// Asks the settings control in the posting window to take controller focus.
    public static let focusSettingsControl = Notification.Name("ChiakiNG.focusSettingsControl")
    /// Asks the settings tab strip in the posting window to take controller focus.
    public static let focusSettingsTabs = Notification.Name("ChiakiNG.focusSettingsTabs")
    /// Announces that the settings panel in the posting window finished sliding in, so its opening focus can
    /// be measured where the panel came to rest.
    public static let settingsPanelSettled = Notification.Name("ChiakiNG.settingsPanelSettled")
    /// Asks the library's main content in the posting window to take controller focus.
    public static let focusLibraryContent = Notification.Name("ChiakiNG.focusLibraryContent")
    /// Asks the library header in the posting window to take controller focus.
    public static let focusLibraryHeader = Notification.Name("ChiakiNG.focusLibraryHeader")
    /// Announces that the active controller family changed, so button glyphs can be redrawn.
    public static let controllerFamilyChanged = Notification.Name("ChiakiNG.controllerFamilyChanged")
    /// Asks the stream menu in the posting window to open with controller focus on its panel's tab.
    public static let focusStreamMenu = Notification.Name("ChiakiNG.focusStreamMenu")
    /// Asks the stream menu in the posting window to open with controller focus on the dock's Settings item.
    public static let focusStreamMenuSettings = Notification.Name("ChiakiNG.focusStreamMenuSettings")
    /// Asks the quit control in the posting window to take controller focus.
    public static let focusQuitControl = Notification.Name("ChiakiNG.focusQuitControl")
    /// Asks the live developer log button in the posting window to take controller focus.
    public static let focusLiveLogButton = Notification.Name("ChiakiNG.focusLiveLogButton")
    /// Asks the live developer log in the posting window to open or close; it takes controller focus when it
    /// opens in controller mode.
    public static let toggleLiveLog = Notification.Name("ChiakiNG.toggleLiveLog")
    /// Asks the menu stop that opens the live developer log, in the library rail or the stream menu dock, to
    /// take controller focus.
    public static let focusLiveLogOpener = Notification.Name("ChiakiNG.focusLiveLogOpener")
    /// Announces that the stream controls in the posting window were dismissed.
    public static let streamControlsDismissed = Notification.Name("ChiakiNG.streamControlsDismissed")
    /// Posted by a controller shortcut to mute or unmute the stream microphone of the window in `object`.
    public static let toggleStreamMicrophone = Notification.Name("ChiakiNG.toggleStreamMicrophone")
    /// Posted by the Stream Diagnostics Detail command to step the diagnostics overlay of the window in `object` to
    /// its next level.
    public static let cycleStreamDiagnosticsLevel = Notification.Name("ChiakiNG.cycleStreamDiagnosticsLevel")
    /// Posted by the Stream Diagnostics Glass command to step the diagnostics overlay of the window in `object` to
    /// its next glass.
    public static let cycleStreamDiagnosticsGlass = Notification.Name("ChiakiNG.cycleStreamDiagnosticsGlass")
}
