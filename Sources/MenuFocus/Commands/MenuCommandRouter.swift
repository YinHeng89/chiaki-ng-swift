import Foundation
import PlatformUI
import SwiftUI

/// Delivers the controller commands the focus engine does not handle itself to the views that asked for
/// them.
///
/// Tab switching, Options, the stream menu shortcut and the on-screen keyboard's shortcuts reach views as
/// typed ``MenuCommandEvent`` values tagged with their window, instead of untyped notifications. Each
/// subscriber gets its own stream from ``events()``; a view usually subscribes through
/// ``SwiftUICore/View/onMenuCommand(_:perform:)`` and compares the event's window with its own.
@MainActor
public final class MenuCommandRouter {
    private var subscribers = [UUID: AsyncStream<MenuCommandEvent>.Continuation]()

    /// Creates a router with no subscribers.
    public init() {
    }

    /// Starts a subscription.
    ///
    /// The stream ends when the subscriber stops iterating it.
    ///
    /// - Returns: Every command routed from now on.
    public func events() -> AsyncStream<MenuCommandEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<MenuCommandEvent>
            .makeStream(bufferingPolicy: .bufferingNewest(16))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.subscribers[id] = nil
            }
        }
        return stream
    }

    /// Routes a command to every subscriber.
    ///
    /// - Parameters:
    ///   - command: The command.
    ///   - window: The window it belongs to, or `nil` for whichever window is key.
    public func send(_ command: MenuCommand, to window: PlatformWindow?) {
        let event = MenuCommandEvent(command: command, window: window)
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    /// The number of live subscriptions.
    public var subscriberCount: Int {
        subscribers.count
    }
}

/// Delivers controller commands to a view for as long as it is shown.
///
/// Apply it with ``SwiftUICore/View/onMenuCommand(_:perform:)`` for the routed commands, or with
/// ``SwiftUICore/View/onPerformedMenuCommand(_:perform:)`` to watch every command the navigator performs. The
/// action always runs the closure from the view's latest update.
public struct MenuCommandSubscription: ViewModifier {
    @MainActor
    private final class Action {
        var perform: (MenuCommandEvent) -> Void = { _ in
        }
    }

    private let commands: Set<MenuCommand>
    private let source: KeyPath<PlatformMenuNavigator, MenuCommandRouter>
    private let perform: (MenuCommandEvent) -> Void
    @Environment(\.menuNavigator) private var navigator
    @State private var action = Action()

    /// Creates the subscription.
    ///
    /// - Parameters:
    ///   - commands: The commands to receive.
    ///   - source: The navigator's router to listen to: ``MenuNavigator/commands`` or
    ///     ``MenuNavigator/performed``.
    ///   - perform: Runs for each command, with the window it belongs to.
    public init(
        commands: Set<MenuCommand>,
        source: KeyPath<PlatformMenuNavigator, MenuCommandRouter> = \.commands,
        perform: @escaping (MenuCommandEvent) -> Void
    ) {
        self.commands = commands
        self.source = source
        self.perform = perform
    }

    /// Subscribes while the view is shown.
    ///
    /// - Parameter content: The receiving view.
    /// - Returns: The view with the subscription attached.
    public func body(content: Content) -> some View {
        action.perform = perform
        return content.task(id: navigator.map(ObjectIdentifier.init)) {
            guard let navigator else {
                return
            }
            for await event in navigator[keyPath: source].events() where commands.contains(event.command) {
                action.perform(event)
            }
        }
    }
}

extension View {
    /// Receives routed controller commands, such as tab switches or Options, while the view is shown.
    ///
    /// - Parameters:
    ///   - commands: The commands to receive.
    ///   - perform: Runs for each command; compare ``MenuCommandEvent/targets(_:)`` with the view's window.
    /// - Returns: The view with ``MenuCommandSubscription`` applied.
    public func onMenuCommand(
        _ commands: Set<MenuCommand>,
        perform: @escaping (MenuCommandEvent) -> Void
    ) -> some View {
        modifier(MenuCommandSubscription(commands: commands, perform: perform))
    }

    /// Watches every command the navigator performs while the view is shown, including the directions,
    /// Confirm and Back it handles itself, without taking them from the focus engine.
    ///
    /// - Parameters:
    ///   - commands: The commands to watch.
    ///   - perform: Runs for each command; compare ``MenuCommandEvent/targets(_:keyWindow:)`` with the view's
    ///     window.
    /// - Returns: The view with ``MenuCommandSubscription`` applied to ``MenuNavigator/performed``.
    public func onPerformedMenuCommand(
        _ commands: Set<MenuCommand> = Set(MenuCommand.allCases),
        perform: @escaping (MenuCommandEvent) -> Void
    ) -> some View {
        modifier(MenuCommandSubscription(commands: commands, source: \.performed, perform: perform))
    }
}
