import DesignSystem
import SwiftUI

extension EnvironmentValues {
    /// Whether a library menu stop has controller focus, so the north button returns to the content.
    @Entry var libraryMenuFocused = false
}

/// The controller prompt in a library heading for the north button: "Menu" while the content has focus,
/// and the way back to the tab, such as "Back to Consoles", while a menu stop has it.
struct LibraryMenuHint: View {
    /// The tab whose heading shows the prompt.
    let section: LibrarySection
    @Environment(\.libraryMenuFocused) private var menuFocused

    /// The view.
    var body: some View {
        ControllerPrompt(button: .north, text: Self.title(menuFocused: menuFocused, section: section))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The prompt's wording.
    ///
    /// - Parameters:
    ///   - menuFocused: Whether a menu stop has controller focus.
    ///   - section: The tab whose heading shows the prompt.
    /// - Returns: "Back to" and the tab's name while the menu has focus, otherwise "Menu".
    static func title(menuFocused: Bool, section: LibrarySection) -> LocalizedStringResource {
        menuFocused
            ? .libraryMenuHintBackTo(section: String(localized: section.title))
            : .libraryMenuHintMenu
    }
}
