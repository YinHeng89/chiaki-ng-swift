import ChiakiClients
import SwiftUI

/// Mirrors a stream host's reducer state into the controller layer's `streamNavigationActive`.
///
/// The stream hosts, the console and cloud stream and the guest stream, are the only writers of that flag: each
/// applies this modifier with its feature's `controllerNavigationActive`, and the flag drops back to `false`
/// when the host goes away.
struct StreamNavigationMirror: ViewModifier {
    /// The controller driving menus, whose stream navigation flag this modifier writes.
    @Environment(\.controllerNavigation) private var controllerNavigation

    /// Whether the host's reducer state says controller input drives the app rather than the game.
    let active: Bool

    /// Writes ``active`` now and on every change, and `false` when the host disappears.
    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, active in
                controllerNavigation?.streamNavigationActive = active
            }
            .onDisappear {
                controllerNavigation?.streamNavigationActive = false
            }
    }
}
