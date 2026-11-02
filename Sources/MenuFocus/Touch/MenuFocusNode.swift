#if os(iOS)
    import Foundation
    import Observation
    import SwiftUI
    import UIKit

    /// One level of key handling on iOS: the handlers a view attached with the focus modifiers.
    ///
    /// Nodes form a chain from a focus stop's leaf up through its ancestors. The touch navigator delivers a
    /// synthesised key press to the focused stop's leaf; each node offers it to its handlers, newest first,
    /// then its exit and move commands, and passes it to its parent when nothing used it.
    @MainActor
    public final class MenuFocusNode {
        /// A key handler on a node.
        struct KeyHandler {
            /// The keys handled, or `nil` for every key.
            let keys: Set<KeyEquivalent>?
            /// The phases handled.
            let phases: MenuKeyPress.Phases
            /// Returns whether the press was used.
            let action: (MenuKeyPress) -> MenuKeyPress.Result
        }

        /// The enclosing node.
        weak var parent: MenuFocusNode?

        /// The key handlers, oldest first.
        var keyHandlers = [KeyHandler]()

        /// The action for Escape, from ``SwiftUI/View/onMenuExitCommand(perform:)``.
        var exit: (() -> Void)?

        /// The action for arrows, from ``SwiftUI/View/onMenuMoveCommand(perform:)``.
        var move: ((MenuMoveDirection) -> Void)?

        /// Creates an empty node.
        public init() {
        }

        /// Offers a key press to this node.
        ///
        /// - Parameter press: The press.
        /// - Returns: Whether the node used it.
        func handle(_ press: MenuKeyPress) -> Bool {
            for handler in keyHandlers.reversed() where handler.phases.contains(press.phase) {
                if let keys = handler.keys, !keys.contains(press.key) {
                    continue
                }
                if handler.action(press) == .handled {
                    return true
                }
            }
            guard press.phase == .down else {
                return false
            }
            if press.key == .escape, let exit {
                exit()
                return true
            }
            if let move, let direction = MenuMoveDirection(press.key) {
                move(direction)
                return true
            }
            return false
        }
    }

    /// Attaches key handlers to a view on iOS by giving it a ``MenuFocusNode`` below its parent's.
    struct MenuFocusNodeHost: ViewModifier {
        @Environment(\.menuFocusNode) private var parent
        @State private var node = MenuFocusNode()

        /// Installs this view's handlers on its node.
        let configure: (MenuFocusNode) -> Void

        /// Rebuilds the node's handlers from the view's latest closures and publishes the node.
        ///
        /// - Parameter content: The view.
        /// - Returns: The view with its node in the environment.
        func body(content: Content) -> some View {
            node.parent = parent
            node.keyHandlers.removeAll()
            node.exit = nil
            node.move = nil
            configure(node)
            return content.environment(\.menuFocusNode, node)
        }
    }

    /// The innermost focusable node inside a focus stop, reported up the view tree so the stop delivers key
    /// presses to it.
    struct MenuFocusLeaf: Equatable {
        /// The node.
        let node: MenuFocusNode

        /// Whether the node's view can take focus.
        let enabled: Bool

        /// Whether two leaves are the same node in the same state.
        ///
        /// - Parameters:
        ///   - first: One leaf.
        ///   - second: The other leaf.
        /// - Returns: `true` for the same node and enabled state.
        nonisolated static func == (first: MenuFocusLeaf, second: MenuFocusLeaf) -> Bool {
            first.node === second.node && first.enabled == second.enabled
        }
    }

    /// Collects the focusable leaves below a focus stop.
    struct MenuFocusLeafKey: PreferenceKey {
        /// No leaves.
        static let defaultValue: [MenuFocusLeaf] = []

        /// Appends a child's leaves.
        ///
        /// - Parameters:
        ///   - value: The leaves so far.
        ///   - nextValue: The next child's leaves.
        static func reduce(value: inout [MenuFocusLeaf], nextValue: () -> [MenuFocusLeaf]) {
            value.append(contentsOf: nextValue())
        }
    }

    /// Marks a view as the focusable leaf of the focus stop around it, so key presses reach its handlers.
    struct MenuFocusableLeaf: ViewModifier {
        @Environment(\.menuFocusNode) private var parent
        @Environment(\.isEnabled) private var enabled
        @State private var node = MenuFocusNode()

        /// Whether the view takes focus.
        let focusable: Bool

        /// Publishes the leaf to the enclosing stop.
        ///
        /// - Parameter content: The view.
        /// - Returns: The view reporting itself as a leaf.
        func body(content: Content) -> some View {
            node.parent = parent
            return content
                .environment(\.menuFocusNode, node)
                .transformPreference(MenuFocusLeafKey.self) { leaves in
                    leaves = [MenuFocusLeaf(node: node, enabled: focusable && enabled)]
                }
        }
    }

    /// A control the touch navigator can focus, registered by ``SwiftUI/View/menuFocused(_:equals:)``.
    ///
    /// The stop records the control's frame and window, and the closures that focus it, unfocus it and start
    /// or stop text entry, which write the bound ``MenuFocusState``.
    @MainActor
    public final class MenuFocusStop {
        /// The stop's identity.
        public let id = UUID()

        /// The control's frame in global coordinates.
        public var frame = CGRect.zero

        /// Whether the control can take focus.
        public var enabled = true

        /// The window the control is in.
        public weak var window: UIWindow?

        /// The node that receives key presses while the stop has focus.
        var leaf = MenuFocusNode()

        /// Gives the control focus.
        var claim: () -> Void = {
        }

        /// Takes focus from the control.
        var release: () -> Void = {
        }

        /// Starts or stops text entry in the control.
        var edit: (Bool) -> Void = { _ in
        }

        /// Whether the control is in text entry.
        var isEditing: () -> Bool = {
            false
        }

        /// Creates an unregistered stop.
        public init() {
        }

        /// Delivers a key press, down then up, to the stop's node chain, from its leaf up to the first node
        /// that handles it.
        ///
        /// - Parameters:
        ///   - key: The key.
        ///   - characters: The characters the key types.
        /// - Returns: Whether a node handled the press.
        @discardableResult
        func deliver(_ key: KeyEquivalent, characters: String = "") -> Bool {
            var handled = false
            for phase in [MenuKeyPress.Phases.down, .up] {
                let press = MenuKeyPress(key: key, characters: characters, modifiers: [], phase: phase)
                var node: MenuFocusNode? = leaf
                while let current = node {
                    if current.handle(press) {
                        handled = true
                        break
                    }
                    node = current.parent
                }
            }
            return handled
        }
    }

    /// The value a ``MenuFocusState`` holds, shared by reference between the state and its bindings.
    @MainActor
    @Observable
    public final class MenuFocusBox<Value: Hashable> {
        /// The focused value.
        public var value: Value

        /// Creates a box.
        ///
        /// - Parameter value: The initial value.
        public init(_ value: Value) {
            self.value = value
        }
    }

    extension EnvironmentValues {
        /// The key handling node of the enclosing view, the parent of any node created below it.
        @Entry var menuFocusNode: MenuFocusNode?

        /// The window focus stops below register in, when a view knows it.
        @Entry var menuFocusWindow: UIWindow?
    }

    /// Registers a control as a touch navigator focus stop bound to a ``MenuFocusState`` value.
    ///
    /// The stop's frame follows the control's geometry; focusing it writes the bound value, and the bound
    /// value changing reports focus gained or lost to the navigator. Text fields inside the control follow
    /// the stop's editing state.
    struct MenuFocusBinding<Value: Hashable>: ViewModifier {
        @Environment(\.menuFocusNode) private var parent
        @Environment(\.menuFocusWindow) private var window
        @Environment(\.isEnabled) private var enabled
        @Environment(\.menuNavigator) private var navigator
        @State private var own = MenuFocusNode()
        @State private var stop = MenuFocusStop()
        @State private var leaf: MenuFocusLeaf?
        @FocusState private var editing: Bool

        /// The bound focus state's storage.
        let box: MenuFocusBox<Value>

        /// The value that means this control has focus.
        let focusedValue: Value

        /// The value the state returns to when the control loses focus.
        let restingValue: Value

        private var isFocused: Bool {
            box.value == focusedValue
        }

        /// Registers the stop and keeps its frame, window and state current.
        ///
        /// - Parameter content: The control.
        /// - Returns: The control as a focus stop.
        func body(content: Content) -> some View {
            own.parent = parent
            stop.leaf = leaf?.node ?? own
            stop.enabled = enabled && (leaf?.enabled ?? true)
            stop.window = window
            return content
                .environment(\.menuItemFocused, isFocused)
                .focused($editing)
                .onPreferenceChange(MenuFocusLeafKey.self) { leaves in
                    MainActor.assumeIsolated {
                        leaf = leaves.first
                    }
                }
                .transformPreference(MenuFocusLeafKey.self) { leaves in
                    leaves = []
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    stop.frame = frame
                }
                .onChange(of: isFocused, initial: true) { _, focused in
                    if focused {
                        navigator?.focusStops.gained(stop)
                    } else {
                        editing = false
                        navigator?.focusStops.lost(stop)
                    }
                }
                .onChange(of: editing) { _, editing in
                    if editing, !isFocused {
                        box.value = focusedValue
                    }
                }
                .onAppear {
                    attach()
                }
                .onDisappear {
                    detach()
                }
        }

        private func attach() {
            let created = stop
            let editingBinding = $editing
            let box = box
            let focusedValue = focusedValue
            let restingValue = restingValue
            created.claim = {
                box.value = focusedValue
            }
            created.release = {
                if box.value == focusedValue {
                    box.value = restingValue
                }
            }
            created.edit = { editing in
                editingBinding.wrappedValue = editing
            }
            created.isEditing = {
                editingBinding.wrappedValue
            }
            navigator?.focusStops.register(created)
            if isFocused {
                navigator?.focusStops.gained(created)
            }
        }

        private func detach() {
            navigator?.focusStops.unregister(stop)
            if isFocused {
                box.value = restingValue
            }
        }
    }
#endif
