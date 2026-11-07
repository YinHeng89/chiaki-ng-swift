import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

extension EnvironmentValues {
    /// Whether the quit button is shown beside Settings.
    @Entry var quitControlShown = false
}

#if os(macOS)
    /// The quit button beside Settings; it asks the window's root whether to quit.
    struct AppQuitButton: View {
        @Environment(\.requestQuit) private var requestQuit

        /// The view.
        var body: some View {
            FocusButton {
                requestQuit(.button)
            } label: {
                AppIcon.quit.image.frame(width: 32, height: 32)
            }
            .glassControlStyle().focusBorderShape(.circle)
            .help(.appQuitButton).accessibilityLabel(.appQuitButton)
        }
    }
#else
    /// Nothing: quitting is left to the system.
    struct AppQuitButton: View {
        /// The view.
        var body: some View {
            EmptyView()
        }
    }
#endif
