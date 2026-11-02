import MenuFocus

/// The navigator every hosted-window focus test shares, standing in for the one the app creates at its
/// composition root.
///
/// Focus suites run serialized, so one navigator with one handler stack matches the app, where every
/// window shares the app's navigator.
@MainActor
public enum MenuFocusTestEnvironment {
    /// The policy behind ``navigator``.
    public static let policy = StandaloneMenuInputPolicy()

    /// The shared test navigator.
    public static let navigator = PlatformMenuNavigator(policy: policy)

    /// The controller navigation hosted stream views share, standing in for the app's input services.
    public static let controllerNavigation = RecordingControllerNavigation()
}

/// The shared test navigator, ``MenuFocusTestEnvironment/navigator``.
@MainActor
public var testNavigator: PlatformMenuNavigator {
    MenuFocusTestEnvironment.navigator
}

/// The shared test controller navigation, ``MenuFocusTestEnvironment/controllerNavigation``.
@MainActor
public var testControllerNavigation: RecordingControllerNavigation {
    MenuFocusTestEnvironment.controllerNavigation
}
