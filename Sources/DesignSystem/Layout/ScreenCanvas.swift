import SwiftUI

/// Measures the scene and publishes its ``ScreenLayout`` to the views below.
///
/// Apply it once at the root of a scene with ``SwiftUICore/View/screenLayout()``, on every platform, so a
/// shrunk Mac window and an iPad in Split View take the same compact arrangement as a phone.
public struct ScreenCanvas: ViewModifier {
    /// Creates the measuring modifier.
    public init() {
    }

    /// Publishes the layout measured from the available space.
    ///
    /// - Parameter content: The scene's root view.
    /// - Returns: The root view with ``SwiftUICore/EnvironmentValues/screenLayout`` set.
    public func body(content: Content) -> some View {
        GeometryReader { proxy in
            content.environment(
                \.screenLayout,
                ScreenLayout.measured(size: proxy.size, safeArea: proxy.safeAreaInsets)
            )
        }
    }
}

extension View {
    /// Measures the scene and publishes its layout traits to the views below.
    ///
    /// - Returns: The view wrapped in ``ScreenCanvas``.
    public func screenLayout() -> some View {
        modifier(ScreenCanvas())
    }
}
