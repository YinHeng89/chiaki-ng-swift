import SwiftUI

/// Asks the window's ``RootFeature`` whether to quit, read from the environment as `requestQuit`.
///
/// ``RootView`` provides it for its window; it presents the quit alert as the root's destination.
struct RequestQuitAction {
    private let request: @MainActor (RootFeature.QuitOrigin) -> Void

    /// Creates the action.
    ///
    /// - Parameter request: Asks to quit from an origin.
    init(_ request: @escaping @MainActor (RootFeature.QuitOrigin) -> Void) {
        self.request = request
    }

    /// Asks whether to quit.
    ///
    /// - Parameter origin: What asked.
    @MainActor
    func callAsFunction(_ origin: RootFeature.QuitOrigin) {
        request(origin)
    }
}

extension EnvironmentValues {
    /// Asks the window's root whether to quit.
    @Entry var requestQuit = RequestQuitAction { _ in
    }
}
