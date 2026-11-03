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
        #if os(iOS)
            KeyboardIndependentCanvas(content: content)
        #else
            GeometryReader { proxy in
                content.environment(
                    \.screenLayout,
                    ScreenLayout.measured(size: proxy.size, safeArea: proxy.safeAreaInsets)
                )
            }
        #endif
    }
}

#if os(iOS)
    /// Measures the scene as if the software keyboard were hidden, so showing it neither reflows the layout nor
    /// counts its height as a bottom inset on top of the space the views already give up to it.
    private struct KeyboardIndependentCanvas<Content: View>: View {
        let content: Content
        @State private var layout: ScreenLayout?

        var body: some View {
            ZStack {
                if let layout {
                    content.environment(\.screenLayout, layout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onGeometryChange(for: ScreenLayout.self) { geometry in
                            ScreenLayout.measured(size: geometry.size, safeArea: geometry.safeAreaInsets)
                        } action: { measured in
                            layout = measured
                        }
                }
                .ignoresSafeArea(.keyboard)
            }
        }
    }
#endif

extension View {
    /// Measures the scene and publishes its layout traits to the views below.
    ///
    /// - Returns: The view wrapped in ``ScreenCanvas``.
    public func screenLayout() -> some View {
        modifier(ScreenCanvas())
    }
}
