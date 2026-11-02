import Foundation
import Observation
import SwiftUI

/// Records which presentations currently own controller input, so content underneath stops reacting.
///
/// A modal, overlay or panel adds its presentation id to ``presentations`` while it is shown; handlers of
/// the content underneath check ``isBlocking`` and step aside. Confirmation prompts that must also stop
/// Options and other shortcuts add their id to ``prompts`` as well. Release the id as soon as the user
/// chooses, not when the view disappears, because a fade-out keeps the view alive. For the common case
/// apply ``SwiftUICore/View/menuInputBlocking(_:prompt:)``.
@MainActor
@Observable
public final class MenuInputGate {
    /// The presentations that own input now.
    public var presentations = Set<UUID>()

    /// The confirmation prompts that own input now; each is also in ``presentations``.
    public var prompts = Set<UUID>()

    /// Creates a gate with nothing presented.
    public init() {
    }

    /// Whether any presentation owns input, so content underneath must ignore commands.
    public var isBlocking: Bool {
        !presentations.isEmpty
    }

    /// Whether a confirmation prompt is showing.
    public var isPrompting: Bool {
        !prompts.isEmpty
    }

    /// Whether a presentation other than the given one owns input.
    ///
    /// - Parameter presentation: The caller's own presentation id.
    /// - Returns: `true` when something else is presented above or beside the caller.
    public func isBlocking(besides presentation: UUID) -> Bool {
        !presentations.subtracting([presentation]).isEmpty
    }

    /// Takes input for a presentation.
    ///
    /// - Parameters:
    ///   - presentation: The presentation's id.
    ///   - prompt: Whether it is a confirmation prompt that also stops shortcuts.
    public func block(_ presentation: UUID, prompt: Bool = false) {
        presentations.insert(presentation)
        if prompt {
            prompts.insert(presentation)
        }
    }

    /// Returns input from a presentation. Releasing an id that is not blocking does nothing.
    ///
    /// - Parameter presentation: The presentation's id.
    public func release(_ presentation: UUID) {
        presentations.remove(presentation)
        prompts.remove(presentation)
    }
}

/// Takes controller input for a presentation in the navigator's ``MenuInputGate`` while it is active.
///
/// Apply it with ``SwiftUICore/View/menuInputBlocking(_:prompt:)``. Input is released as soon as `active`
/// turns `false`, which callers should do the moment the user chooses, and at the latest when the view
/// disappears.
public struct MenuInputBlocking: ViewModifier {
    private let active: Bool
    private let prompt: Bool
    @Environment(\.menuNavigator) private var navigator
    @State private var presentation = UUID()

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - active: Whether the presentation owns input now.
    ///   - prompt: Whether it is a confirmation prompt that also stops shortcuts.
    public init(active: Bool, prompt: Bool) {
        self.active = active
        self.prompt = prompt
    }

    /// Blocks and releases input with the presentation.
    ///
    /// - Parameter content: The presentation.
    /// - Returns: The presentation, blocking input while active.
    public func body(content: Content) -> some View {
        content
            .onAppear {
                update(active)
            }
            .onChange(of: active) { _, active in
                update(active)
            }
            .onDisappear {
                navigator?.inputGate.release(presentation)
            }
    }

    private func update(_ active: Bool) {
        guard let navigator else {
            return
        }
        if active {
            navigator.inputGate.block(presentation, prompt: prompt)
        } else {
            navigator.inputGate.release(presentation)
        }
    }
}

extension View {
    /// Makes content underneath ignore controller input while this presentation is active.
    ///
    /// - Parameters:
    ///   - active: Whether the presentation owns input now.
    ///   - prompt: Whether it is a confirmation prompt that also stops shortcuts.
    /// - Returns: The view with ``MenuInputBlocking`` applied.
    public func menuInputBlocking(_ active: Bool = true, prompt: Bool = false) -> some View {
        modifier(MenuInputBlocking(active: active, prompt: prompt))
    }
}
