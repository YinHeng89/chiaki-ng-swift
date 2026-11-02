import PlatformUI
import SwiftUI

/// Registers a view's navigation handlers on the navigator's ``MenuHandlerStack`` while the view is shown.
///
/// The handlers are registered when the view appears with `enabled` true, removed when it disappears or
/// becomes disabled, and always call the closures from the view's latest update, so they never act on
/// state captured when they were registered. Apply it with
/// ``SwiftUICore/View/menuHandlers(enabled:move:activate:modalActivate:back:)``.
public struct MenuHandlers: ViewModifier {
    @MainActor
    private final class Registration {
        var move: MenuHandlerStack.FocusMoveHandler?
        var activate: MenuHandlerStack.WindowHandler?
        var modalActivate: MenuHandlerStack.WindowHandler?
        var back: MenuHandlerStack.WindowHandler?
        var ids = [MenuHandlerID]()
        weak var stack: MenuHandlerStack?

        func register(on stack: MenuHandlerStack) {
            guard ids.isEmpty else {
                return
            }
            self.stack = stack
            if move != nil {
                ids.append(stack.registerFocusMove { [weak self] window, direction in
                    self?.move?(window, direction) ?? false
                })
            }
            if activate != nil {
                ids.append(stack.registerActivation { [weak self] window in
                    self?.activate?(window) ?? false
                })
            }
            if modalActivate != nil {
                ids.append(stack.registerModalActivation { [weak self] window in
                    self?.modalActivate?(window) ?? false
                })
            }
            if back != nil {
                ids.append(stack.registerBack { [weak self] window in
                    self?.back?(window) ?? false
                })
            }
        }

        func unregister() {
            for id in ids {
                stack?.unregister(id)
            }
            ids.removeAll()
        }
    }

    private let enabled: Bool
    private let move: MenuHandlerStack.FocusMoveHandler?
    private let activate: MenuHandlerStack.WindowHandler?
    private let modalActivate: MenuHandlerStack.WindowHandler?
    private let back: MenuHandlerStack.WindowHandler?
    @Environment(\.menuNavigator) private var navigator
    @State private var registration = Registration()

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - enabled: Whether the handlers are registered; they are removed while this is `false`.
    ///   - move: Answers direction presses.
    ///   - activate: Answers confirm on ordinary content.
    ///   - modalActivate: Answers confirm while the view is a modal that owns input.
    ///   - back: Answers back.
    public init(
        enabled: Bool,
        move: MenuHandlerStack.FocusMoveHandler?,
        activate: MenuHandlerStack.WindowHandler?,
        modalActivate: MenuHandlerStack.WindowHandler?,
        back: MenuHandlerStack.WindowHandler?
    ) {
        self.enabled = enabled
        self.move = move
        self.activate = activate
        self.modalActivate = modalActivate
        self.back = back
    }

    /// Keeps the registration's closures current and registers or removes them with the view's lifetime.
    ///
    /// - Parameter content: The view that owns the handlers.
    /// - Returns: The view with its handlers registered while shown.
    public func body(content: Content) -> some View {
        registration.move = move
        registration.activate = activate
        registration.modalActivate = modalActivate
        registration.back = back
        return content
            .onAppear {
                update(enabled: enabled)
            }
            .onDisappear {
                registration.unregister()
            }
            .onChange(of: enabled) { _, enabled in
                update(enabled: enabled)
            }
    }

    private func update(enabled: Bool) {
        guard enabled, let navigator else {
            registration.unregister()
            return
        }
        registration.register(on: navigator.handlers)
    }
}

extension View {
    /// Registers navigation handlers while the view is shown and enabled.
    ///
    /// Each handler receives the window the command belongs to; it must check that the window is its own
    /// and return `false` when it has nothing to do.
    ///
    /// - Parameters:
    ///   - enabled: Whether the handlers are registered.
    ///   - move: Answers direction presses.
    ///   - activate: Answers confirm on ordinary content.
    ///   - modalActivate: Answers confirm while the view is a modal that owns input.
    ///   - back: Answers back.
    /// - Returns: The view with ``MenuHandlers`` applied.
    public func menuHandlers(
        enabled: Bool = true,
        move: MenuHandlerStack.FocusMoveHandler? = nil,
        activate: MenuHandlerStack.WindowHandler? = nil,
        modalActivate: MenuHandlerStack.WindowHandler? = nil,
        back: MenuHandlerStack.WindowHandler? = nil
    ) -> some View {
        modifier(MenuHandlers(
            enabled: enabled,
            move: move,
            activate: activate,
            modalActivate: modalActivate,
            back: back
        ))
    }
}
