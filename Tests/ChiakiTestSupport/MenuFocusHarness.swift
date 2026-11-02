#if os(macOS)
    import AppKit
    import MenuFocus
    import PlatformUI

    /// A real, titled window, kept off screen, for driving a view with controller commands in a test.
    ///
    /// The harness cannot become key in every environment, cannot open native menus and does not reproduce
    /// every SwiftUI focus race; a test that passes both with and without a fix proves nothing about it.
    @MainActor
    public final class MenuFocusHarness {
        /// The test window.
        public let window: PlatformWindow

        /// The window's content view.
        public let host: NSView

        /// The navigator commands are performed with.
        public let navigator: AppKitMenuNavigator

        /// Creates the window and its content.
        ///
        /// - Parameters:
        ///   - width: The content width.
        ///   - height: The content height.
        ///   - navigator: The navigator to perform commands with.
        ///   - content: Builds the content view for the window, usually a ``MenuFocusHostingView``.
        public init(
            width: CGFloat,
            height: CGFloat,
            navigator: AppKitMenuNavigator = MenuFocusTestEnvironment.navigator,
            content: (PlatformWindow) -> NSView
        ) {
            _ = NSApplication.shared
            self.navigator = navigator
            window = HeadlessWindow(
                contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            host = content(window)
            window.contentView = host
        }

        /// The view that has focus.
        public var focusedView: NSView? {
            window.firstResponder as? NSView
        }

        /// The focused view's frame in window coordinates.
        public var focusedFrame: CGRect {
            focusedView.map { view in
                view.convert(view.bounds, to: nil)
            } ?? .zero
        }

        /// Orders the off-screen window in as key, without activating the test process, and lets the content settle.
        public func open() async {
            window.makeKeyAndOrderFront(nil)
            await settle()
        }

        /// Closes any sheet and the window.
        public func close() {
            window.attachedSheet?.close()
            window.contentView = nil
            window.close()
        }

        /// Lays out the content and yields so pending SwiftUI work runs.
        ///
        /// - Parameter view: The view to lay out, the content view when `nil`.
        public func settle(_ view: NSView? = nil) async {
            let target = view ?? host
            for _ in 0..<20 {
                target.layoutSubtreeIfNeeded()
                await Task.yield()
            }
        }

        /// Waits, then settles.
        ///
        /// - Parameter milliseconds: How long to wait.
        public func pause(_ milliseconds: Int) async {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            await settle()
        }

        /// Performs a command in the window and settles.
        ///
        /// - Parameter command: The command.
        public func send(_ command: MenuCommand) async {
            perform([command], in: window)
            await settle()
        }

        /// Performs commands in the window one by one, settling after each.
        ///
        /// - Parameter commands: The commands.
        public func send(_ commands: [MenuCommand]) async {
            for command in commands {
                await send(command)
            }
        }

        /// Performs commands in a sheet one by one, settling after each.
        ///
        /// - Parameters:
        ///   - commands: The commands.
        ///   - sheet: The sheet window.
        public func send(_ commands: [MenuCommand], in sheet: PlatformWindow) async {
            for command in commands {
                perform([command], in: sheet)
                await settle(sheet.contentView)
            }
        }

        /// Performs commands in a window, delivering synthesised keys straight to it.
        ///
        /// - Parameters:
        ///   - commands: The commands.
        ///   - target: The window.
        public func perform(_ commands: [MenuCommand], in target: PlatformWindow) {
            for command in commands {
                navigator.perform(command, in: target) { event in
                    target.sendEvent(event)
                }
            }
        }
    }
#endif
