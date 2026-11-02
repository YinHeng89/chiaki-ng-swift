import Foundation
import PlatformUI

/// The handlers views register to take part in controller navigation, asked newest first.
///
/// A view registers a handler while it is the active level of a menu and removes it when it closes. When a
/// command arrives the navigator asks the matching handlers from the most recent registration back; the
/// first one that returns `true` consumes the command, and when none does the navigator falls back to the
/// platform behaviour (a synthesised arrow key, Space or Escape). A handler must only act for its own
/// window and return `false` when it has nothing to do, so the command still reaches the screen below.
///
/// Prefer the ``SwiftUICore/View/menuHandlers(enabled:move:activate:modalActivate:back:)`` modifier, which
/// registers on appear, removes on disappear and always calls the view's latest closures.
@MainActor
public final class MenuHandlerStack {
    /// Answers a direction press in a window.
    public typealias FocusMoveHandler = @MainActor (PlatformWindow, MenuMoveDirection) -> Bool

    /// Answers confirm, back or text activation in a window.
    public typealias WindowHandler = @MainActor (PlatformWindow) -> Bool

    private struct Entry<Handler> {
        let id: MenuHandlerID
        let handler: Handler
    }

    private var focusMoves = [Entry<FocusMoveHandler>]()
    private var activations = [Entry<WindowHandler>]()
    private var modalActivations = [Entry<WindowHandler>]()
    private var backs = [Entry<WindowHandler>]()
    private var textActivations = [Entry<WindowHandler>]()

    /// Creates an empty stack.
    public init() {
    }

    /// Registers a handler for direction presses.
    ///
    /// - Parameter handler: Returns `true` when it moved focus itself.
    /// - Returns: The receipt to pass to ``unregister(_:)``.
    @discardableResult
    public func registerFocusMove(_ handler: @escaping FocusMoveHandler) -> MenuHandlerID {
        let id = MenuHandlerID(kind: .focusMove)
        focusMoves.append(Entry(id: id, handler: handler))
        return id
    }

    /// Registers a handler for confirm on ordinary content.
    ///
    /// - Parameter handler: Returns `true` when it activated something.
    /// - Returns: The receipt to pass to ``unregister(_:)``.
    @discardableResult
    public func registerActivation(_ handler: @escaping WindowHandler) -> MenuHandlerID {
        let id = MenuHandlerID(kind: .activation)
        activations.append(Entry(id: id, handler: handler))
        return id
    }

    /// Registers a handler for confirm while a modal owns input.
    ///
    /// Modal handlers are asked before ordinary activation handlers, and while any is registered the
    /// navigator treats Return and Space from the keyboard as confirm too.
    ///
    /// - Parameter handler: Returns `true` when it activated something.
    /// - Returns: The receipt to pass to ``unregister(_:)``.
    @discardableResult
    public func registerModalActivation(_ handler: @escaping WindowHandler) -> MenuHandlerID {
        let id = MenuHandlerID(kind: .modalActivation)
        modalActivations.append(Entry(id: id, handler: handler))
        return id
    }

    /// Registers a handler for back.
    ///
    /// - Parameter handler: Returns `true` when it handled back.
    /// - Returns: The receipt to pass to ``unregister(_:)``.
    @discardableResult
    public func registerBack(_ handler: @escaping WindowHandler) -> MenuHandlerID {
        let id = MenuHandlerID(kind: .back)
        backs.append(Entry(id: id, handler: handler))
        return id
    }

    /// Registers a handler for confirm on a focused text field.
    ///
    /// The on-screen keyboard registers one per text field so that confirm opens it for the field that has
    /// focus.
    ///
    /// - Parameter handler: Returns `true` when it took over text entry.
    /// - Returns: The receipt to pass to ``unregister(_:)``.
    @discardableResult
    public func registerTextActivation(_ handler: @escaping WindowHandler) -> MenuHandlerID {
        let id = MenuHandlerID(kind: .textActivation)
        textActivations.append(Entry(id: id, handler: handler))
        return id
    }

    /// Removes a handler.
    ///
    /// - Parameter id: The receipt from the registration. Removing a handler twice does nothing.
    public func unregister(_ id: MenuHandlerID) {
        switch id.kind {
        case .focusMove:
            focusMoves.removeAll { $0.id == id }
        case .activation:
            activations.removeAll { $0.id == id }
        case .modalActivation:
            modalActivations.removeAll { $0.id == id }
        case .back:
            backs.removeAll { $0.id == id }
        case .textActivation:
            textActivations.removeAll { $0.id == id }
        }
    }

    /// Asks the direction handlers, newest first.
    ///
    /// - Parameters:
    ///   - direction: The direction pressed.
    ///   - window: The window the press belongs to.
    /// - Returns: Whether a handler moved focus.
    public func performFocusMove(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool {
        focusMoves.reversed().contains { entry in
            entry.handler(window, direction)
        }
    }

    /// Asks the modal activation handlers, newest first.
    ///
    /// - Parameter window: The window confirm belongs to.
    /// - Returns: Whether a handler activated something.
    public func activateModal(in window: PlatformWindow) -> Bool {
        modalActivations.reversed().contains { entry in
            entry.handler(window)
        }
    }

    /// Asks the ordinary activation handlers, newest first.
    ///
    /// - Parameter window: The window confirm belongs to.
    /// - Returns: Whether a handler activated something.
    public func activate(in window: PlatformWindow) -> Bool {
        activations.reversed().contains { entry in
            entry.handler(window)
        }
    }

    /// Asks the back handlers, newest first.
    ///
    /// - Parameter window: The window back belongs to.
    /// - Returns: Whether a handler handled back.
    public func back(in window: PlatformWindow) -> Bool {
        backs.reversed().contains { entry in
            entry.handler(window)
        }
    }

    /// Asks the text activation handlers, newest first.
    ///
    /// - Parameter window: The window whose text field received confirm.
    /// - Returns: Whether a handler took over text entry.
    public func activateText(in window: PlatformWindow) -> Bool {
        textActivations.reversed().contains { entry in
            entry.handler(window)
        }
    }

    /// Whether any modal activation handler is registered.
    public var hasModalActivation: Bool {
        !modalActivations.isEmpty
    }

    /// Removes every handler.
    public func removeAll() {
        focusMoves.removeAll()
        activations.removeAll()
        modalActivations.removeAll()
        backs.removeAll()
        textActivations.removeAll()
    }
}

/// The receipt for a handler registered on a ``MenuHandlerStack``, used to remove it again.
public struct MenuHandlerID: Hashable, Sendable {
    /// What a handler answers.
    public enum Kind: Hashable, Sendable {
        /// A direction press.
        case focusMove
        /// Confirm on ordinary content.
        case activation
        /// Confirm while a modal owns input; asked before ``activation`` handlers.
        case modalActivation
        /// Back.
        case back
        /// Confirm on a focused text field, which may open the on-screen keyboard.
        case textActivation
    }

    /// The registration's unique value.
    public let value: UUID

    /// What the handler answers.
    public let kind: Kind

    /// Creates a receipt.
    ///
    /// - Parameters:
    ///   - value: The registration's unique value.
    ///   - kind: What the handler answers.
    public init(value: UUID = UUID(), kind: Kind) {
        self.value = value
        self.kind = kind
    }
}
