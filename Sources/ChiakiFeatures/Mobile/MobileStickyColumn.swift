import SwiftUI

/// Keeps a side column of a wide touch page in view while the column beside it scrolls: the column scrolls
/// with the page until it reaches the middle of the scroll view's height, then stays centred there.
struct MobileStickyColumn: ViewModifier {
    /// Offsets the content by however far it has scrolled past its centred position.
    func body(content: Content) -> some View {
        content
            .visualEffect { content, proxy in
                let frame = proxy.frame(in: .scrollView)
                let visible = proxy.bounds(of: .scrollView)?.height ?? frame.height
                let centred = max(0, (visible - frame.height) / 2)
                return content.offset(y: max(0, centred - frame.minY))
            }
            .zIndex(1)
    }
}
