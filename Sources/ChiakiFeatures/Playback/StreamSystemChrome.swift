import SwiftUI

/// Keeps the system's own chrome out of a playing stream: hides the home indicator and other persistent system
/// overlays and, on iOS, makes a swipe up from the bottom edge show the indicator first instead of leaving the
/// app at once.
struct StreamSystemChrome: ViewModifier {
    /// Applies the stream's system chrome rules.
    ///
    /// - Parameter content: The stream.
    /// - Returns: The stream with the system overlays hidden and the bottom edge gesture deferred.
    func body(content: Content) -> some View {
        content
            .persistentSystemOverlays(.hidden)
        #if os(iOS)
            .defersSystemGestures(on: .bottom)
        #endif
    }
}
