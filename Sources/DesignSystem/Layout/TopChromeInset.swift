import SwiftUI

/// Pads a screen's content below the window's top chrome by ``ScreenLayout/topChromeInset``.
///
/// Apply it with ``SwiftUICore/View/topChromeInset()``.
public struct TopChromeInset: ViewModifier {
    @Environment(\.screenLayout) private var layout

    /// Creates the inset.
    public init() {
    }

    /// Adds the top padding.
    ///
    /// - Parameter content: The screen's content.
    /// - Returns: The content pushed below the top chrome.
    public func body(content: Content) -> some View {
        content.padding(.top, layout.topChromeInset)
    }
}

extension View {
    /// Keeps the view clear of the window's top chrome.
    ///
    /// - Returns: The view with ``TopChromeInset`` applied.
    public func topChromeInset() -> some View {
        modifier(TopChromeInset())
    }
}
