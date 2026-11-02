#if os(macOS)
    import AppKit
    import MenuFocus
    import SwiftUI

    /// Hosts a SwiftUI view for a focus test with the shared test navigator in its environment.
    @MainActor
    public final class MenuFocusHostingView<Content: View>: NSHostingView<MenuFocusRoot<Content>> {
        /// Hosts a view.
        ///
        /// - Parameter rootView: The view under test.
        public convenience init(rootView: Content) {
            self.init(rootView: MenuFocusRoot(content: rootView))
        }

        /// Hosts an already wrapped root.
        ///
        /// - Parameter rootView: The wrapped view.
        public required init(rootView: MenuFocusRoot<Content>) {
            super.init(rootView: rootView)
        }

        /// Unsupported.
        ///
        /// - Parameter coder: Unused.
        @available(*, unavailable)
        public required init?(coder: NSCoder) {
            nil
        }
    }

    /// A view under test with the shared test navigator in its environment.
    public struct MenuFocusRoot<Content: View>: View {
        private let content: Content

        /// Wraps a view.
        ///
        /// - Parameter content: The view under test.
        public init(content: Content) {
            self.content = content
        }

        /// The view with ``MenuFocusTestEnvironment/navigator`` published.
        public var body: some View {
            content.menuNavigator(MenuFocusTestEnvironment.navigator)
        }
    }
#endif
