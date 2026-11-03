import ComposableArchitecture
import Foundation

/// Where the touch library stands above the shown section: the section itself, one console's page, Account and
/// Settings, or one settings page.
///
/// The section, the open cloud game and the open trophy title keep living in their own features; this machine
/// only adds the pages the touch layout pushes over them, and the page Back returns to from each.
@Reducer
public struct MobileShellFeature {
    /// The touch library's page.
    @ObservableState
    public struct State: Equatable {
        /// The page shown over the section.
        public internal(set) var page = Page.home

        /// Whether the last move went deeper, so pages slide in from the trailing edge, or back, so they slide
        /// out to it.
        public internal(set) var forward = true

        /// Creates the touch library on the shown section.
        public init() {
        }
    }

    /// A page of the touch library.
    public enum Page: Hashable, Sendable {
        /// The shown section.
        case home
        /// The page of the console with this id.
        case console(UUID)
        /// The signed-in account, its profiles and the settings categories.
        case account
        /// One settings category.
        case settings(SettingsRoute)

        /// The page Back returns to.
        public var parent: Page {
            switch self {
            case .home, .console, .account:
                .home
            case .settings:
                .account
            }
        }
    }

    /// What moves the touch library between pages.
    public enum Action: Equatable {
        /// A console card was opened from the section.
        case consoleOpened(UUID)
        /// The account control was tapped.
        case accountOpened
        /// A settings category was opened from Account and Settings.
        case settingsOpened(SettingsRoute)
        /// Back was tapped.
        case back
        /// A console this page shows is gone, or a section was chosen.
        case home
    }

    /// Creates the feature.
    public init() {
    }

    /// Moves between pages, refusing moves the current page does not lead to.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .consoleOpened(let id):
                guard state.page == .home else {
                    return .none
                }
                state.forward = true
                state.page = .console(id)
            case .accountOpened:
                state.forward = true
                state.page = .account
            case .settingsOpened(let route):
                switch state.page {
                case .account, .settings:
                    state.forward = true
                    state.page = .settings(route)
                case .home, .console:
                    return .none
                }
            case .back:
                state.forward = false
                state.page = state.page.parent
            case .home:
                state.forward = false
                state.page = .home
            }
            return .none
        }
    }
}
