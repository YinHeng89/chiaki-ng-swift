import SwiftUI

/// The margins every vertical scroll view in the app uses, so content clears the scroll indicator.
///
/// Apply it with ``SwiftUICore/View/appVerticalScrollStyle()``.
public struct AppScrollStyle: ViewModifier {
    /// Creates the scroll style.
    public init() {
    }

    /// Adds the content and indicator margins.
    ///
    /// - Parameter content: A vertical scroll view.
    /// - Returns: The scroll view with the app's margins.
    public func body(content: Content) -> some View {
        content
            .contentMargins(.trailing, 18, for: .scrollContent)
            .contentMargins(.trailing, 6, for: .scrollIndicators)
            .contentMargins(.vertical, 8, for: .scrollIndicators)
    }
}

extension View {
    /// Gives a vertical scroll view the app's content and indicator margins.
    ///
    /// - Returns: The scroll view with ``AppScrollStyle`` applied.
    public func appVerticalScrollStyle() -> some View {
        modifier(AppScrollStyle())
    }
}
