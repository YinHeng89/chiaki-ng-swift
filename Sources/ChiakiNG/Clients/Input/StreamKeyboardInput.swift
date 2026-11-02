import ChiakiFeatures
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation
import PlatformUI
#if os(macOS)
    import AppKit
#else
    import GameController
    import UIKit
#endif

/// The keyboard and mouse in a stream: bound keys and buttons play as a controller, and on a PS5 the keyboard
/// can type on the console instead.
@MainActor
final class StreamKeyboardInput {
    /// What the stream did with a keyboard or mouse event.
    enum Outcome: Equatable {
        /// The event continues to the app.
        case passed
        /// The stream took the event.
        case consumed
        /// The microphone shortcut was pressed.
        case toggleMicrophone
        /// The touchpad shortcut was pressed.
        case toggleTouchpad
        /// A bound key or button changed the keyboard's controller state.
        case mapped
    }

    /// The key code of the microphone shortcut, Command-M.
    static let microphoneKey: UInt16 = 46

    private let environment: InputEnvironment
    private let rawKeyboard: Bool
    private let microphone: Bool
    private var mapper: InputMapper
    private var rawKeys = StreamRawKeyboard()
    private var lastRefused = false
    #if os(macOS)
        private let gate: StreamKeyboardGate
        private var monitor: Any?
    #else
        private var observer: NSObjectProtocol?
    #endif

    /// Creates the keyboard input.
    ///
    /// - Parameters:
    ///   - environment: The player it sends to.
    ///   - surface: The console's touchpad surface, which bound touch keys use.
    ///   - rawKeyboard: Whether the console accepts typed keys.
    ///   - microphone: Whether the stream offers a microphone shortcut.
    init(environment: InputEnvironment, surface: TouchpadSurface, rawKeyboard: Bool, microphone: Bool) {
        self.environment = environment
        self.rawKeyboard = rawKeyboard
        self.microphone = microphone
        mapper = InputMapper(touchSurface: surface)
        #if os(macOS)
            gate = StreamKeyboardGate(environment: environment)
        #endif
    }

    /// The controller state the bound keys and buttons currently hold.
    var state: ControllerState {
        mapper.state(at: ProcessInfo.processInfo.systemUptime, ramp: .keyboard)
    }

    /// Whether the keyboard types on the console rather than playing as a controller.
    ///
    /// - Parameter configuration: The controls configuration.
    /// - Returns: `true` when the console accepts typed keys and the user chose typing.
    func typesOnConsole(_ configuration: ControlsConfiguration) -> Bool {
        rawKeyboard && configuration.keyboardMode == .typeOnConsole
    }

    /// Releases every bound key and button.
    func reset() {
        mapper.reset()
    }

    /// Releases every key typed on the console.
    func releaseTypedKeys() {
        if rawKeys.releaseAll() {
            sendTypedKeys()
        }
    }

    private func sendTypedKeys() {
        let report = rawKeys.report
        let keys = report.keys.withUnsafeBufferPointer {
            Data(buffer: $0)
        }
        if environment.player.sendKeyboardModifiers(report.modifiers, leds: report.leds, keys: keys) {
            lastRefused = false
            return
        }
        guard !lastRefused else {
            return
        }
        lastRefused = true
        @Dependency(\.logger) var logger
        logger.enqueue(.controllerDiagnostic(
            "Stream keyboard: the console did not take a keyboard report"
        ))
    }

    #if os(macOS)
        /// Starts receiving the app's keyboard and mouse events.
        ///
        /// - Parameter consumes: Handles an event and returns whether the stream took it.
        func install(_ consumes: @escaping @MainActor (NSEvent) -> Bool) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [
                .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown,
                .rightMouseUp, .otherMouseDown, .otherMouseUp
            ]) { event in
                let consumed = MainActor.assumeIsolated {
                    consumes(event)
                }
                return consumed
                    ? nil
                    : event
            }
        }

        /// Stops receiving the app's keyboard and mouse events.
        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        /// Handles a keyboard or mouse event during the stream.
        ///
        /// - Parameters:
        ///   - event: The event.
        ///   - phase: Whether the stream has input.
        ///   - configuration: The controls configuration.
        ///   - touchpad: The on-screen touchpad, which takes mouse events over it.
        /// - Returns: What the stream did with the event.
        func handle(
            _ event: NSEvent,
            phase: StreamInputPhase,
            configuration: ControlsConfiguration,
            touchpad: TouchpadInput
        ) -> Outcome {
            if environment.coordinator.menuNavigator?.isControllerEvent(event) == true, phase == .active {
                return .consumed
            }
            if isMicrophoneShortcut(event) {
                return event.type == .keyDown && !event.isARepeat
                    ? .toggleMicrophone
                    : .consumed
            }
            if event.type == .flagsChanged {
                if gate.rejection(of: event, phase: phase) == nil {
                    type(event, phase: phase, configuration: configuration)
                }
                return .passed
            }
            guard !gate.rejects(event, phase: phase) else {
                return .passed
            }
            if event.type == .keyDown, let chord = configuration.touchpadShortcut.key,
               chord.matches(keyCode: Int(event.keyCode), modifiers: ShortcutModifiers(event.modifierFlags)) {
                return event.isARepeat
                    ? .consumed
                    : .toggleTouchpad
            }
            if typesOnConsole(configuration), StreamRawKeyboard.handles(event) {
                if event.type == .keyDown, event.modifierFlags.contains(.command) {
                    return .passed
                }
                type(event, phase: phase, configuration: configuration)
                return .consumed
            }
            return forward(event, configuration: configuration, touchpad: touchpad)
        }

        private func isMicrophoneShortcut(_ event: NSEvent) -> Bool {
            microphone
                && event.type == .keyDown
                && event.keyCode == Self.microphoneKey
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && event.window != nil
                && event.window === environment.player.view.window
        }

        private func type(_ event: NSEvent, phase: StreamInputPhase, configuration: ControlsConfiguration) {
            guard typesOnConsole(configuration),
                  phase == .active,
                  event.window != nil,
                  event.window === environment.player.view.window,
                  rawKeys.apply(event) else {
                return
            }
            sendTypedKeys()
        }

        private func forward(
            _ event: NSEvent,
            configuration: ControlsConfiguration,
            touchpad: TouchpadInput
        ) -> Outcome {
            let isKey = event.type == .keyDown || event.type == .keyUp
            if !isKey, touchpad.contains(event) {
                return .passed
            }
            let source: InputSource = isKey
                ? .macKey
                : .mouseButton
            guard isKey
                ? !typesOnConsole(configuration)
                : configuration.mouseEnabled else {
                return .passed
            }
            if event.modifierFlags.contains(.command), event.type != .keyUp {
                return .passed
            }
            let code = isKey
                ? Int(event.keyCode)
                : event.buttonNumber
            let preset = configuration.keyboardPreset
            guard preset.bindings.contains(where: { $0.source == source && $0.code == code })
            else {
                return .passed
            }
            if isKey && event.isARepeat {
                return .consumed
            }
            if !isKey && clickOutsideStream(event) {
                return .passed
            }
            let down = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
            mapper.press(source: source, code: code, down: down, preset: preset,
                         at: ProcessInfo.processInfo.systemUptime)
            return .mapped
        }

        private func clickOutsideStream(_ event: NSEvent) -> Bool {
            guard [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) else {
                return false
            }
            let view = environment.player.view
            let point = view.convert(event.locationInWindow, from: nil)
            return !view.bounds.contains(point)
        }
    #else
        /// Starts typing the hardware keyboard on the console.
        ///
        /// - Parameter typed: Called on the main actor for each key change.
        func attach(_ typed: @escaping @MainActor @Sendable (GCKeyCode, Bool) -> Void) {
            guard rawKeyboard, observer == nil else {
                return
            }
            bind(GCKeyboard.coalesced, typed)
            observer = NotificationCenter.default.addObserver(
                forName: .GCKeyboardDidConnect, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.bind(GCKeyboard.coalesced, typed)
                }
            }
        }

        /// Stops typing the hardware keyboard on the console.
        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        }

        /// Types one hardware key change on the console.
        ///
        /// - Parameters:
        ///   - code: The key.
        ///   - pressed: Whether it went down.
        ///   - phase: Whether the stream has input.
        ///   - configuration: The controls configuration.
        func type(
            _ code: GCKeyCode,
            pressed: Bool,
            phase: StreamInputPhase,
            configuration: ControlsConfiguration
        ) {
            guard typesOnConsole(configuration),
                  phase == .active,
                  !environment.coordinator.menuInputBlocked,
                  let usage = StreamRawKeyboard.usage(code),
                  rawKeys.press(usage: usage, down: pressed) else {
                return
            }
            sendTypedKeys()
        }

        private func bind(
            _ keyboard: GCKeyboard?,
            _ typed: @escaping @MainActor @Sendable (GCKeyCode, Bool) -> Void
        ) {
            keyboard?.keyboardInput?.keyChangedHandler = { _, _, code, pressed in
                MainActor.assumeIsolated {
                    typed(code, pressed)
                }
            }
        }
    #endif

    #if os(macOS)
        /// Decides whether the stream window may take a keyboard event now, and logs when that changes.
        ///
        /// Keys reach the stream only while it has input, no settings panel, sheet, menu or text field takes them,
        /// the app is active and the event belongs to the stream's key window.
        @MainActor
        private final class StreamKeyboardGate {
            /// Why the stream does not take a keyboard event.
            enum Rejection: Equatable, CustomStringConvertible {
                /// The stream's input is suspended or stopped.
                case noInput(StreamInputPhase)

                /// A settings panel holds the input.
                case panelOpen

                /// Another app is active.
                case appInactive

                /// The stream window is not the key window.
                case notKeyWindow

                /// A sheet is attached to the stream window.
                case sheetAttached

                /// A menu is being tracked.
                case menuTracking

                /// The event belongs to another window.
                case otherWindow

                /// A text field has keyboard focus.
                case textFieldFocused

                /// How the rejection reads in the log.
                var description: String {
                    switch self {
                    case .noInput(let phase):
                        "stream input is \(phase)"
                    case .panelOpen:
                        "a settings panel is open"
                    case .appInactive:
                        "the app is not active"
                    case .notKeyWindow:
                        "the stream window is not the key window"
                    case .sheetAttached:
                        "a sheet is attached"
                    case .menuTracking:
                        "a menu is being tracked"
                    case .otherWindow:
                        "the event belongs to another window"
                    case .textFieldFocused:
                        "a text field has focus"
                    }
                }
            }

            private let environment: InputEnvironment
            private var lastRejection: Rejection?

            /// Creates the gate of a stream window.
            ///
            /// - Parameter environment: The player whose window the gate guards.
            init(environment: InputEnvironment) {
                self.environment = environment
            }

            /// Whether the stream refuses an event, logging when keys stop or start reaching it.
            ///
            /// - Parameters:
            ///   - event: The event.
            ///   - phase: Whether the stream has input.
            /// - Returns: `true` when the stream does not take the event.
            func rejects(_ event: NSEvent, phase: StreamInputPhase) -> Bool {
                if let rejection = rejection(of: event, phase: phase) {
                    if [.keyDown, .keyUp].contains(event.type), rejection != lastRejection {
                        lastRejection = rejection
                        @Dependency(\.logger) var logger
                        logger.enqueue(.controllerDiagnostic("Stream keyboard input ignored: \(rejection)"))
                    }
                    return true
                }
                if lastRejection != nil {
                    lastRejection = nil
                    @Dependency(\.logger) var logger
                    logger.enqueue(.controllerDiagnostic("Stream keyboard input reaches the stream again"))
                }
                return false
            }

            /// Why the stream does not take an event, if it does not.
            ///
            /// - Parameters:
            ///   - event: The event.
            ///   - phase: Whether the stream has input.
            /// - Returns: The reason, or `nil` when the event may reach the stream.
            func rejection(of event: NSEvent, phase: StreamInputPhase) -> Rejection? {
                let window = environment.player.view.window
                if phase != .active {
                    return .noInput(phase)
                }
                if environment.coordinator.menuInputBlocked {
                    return .panelOpen
                }
                if !NSApp.isActive {
                    return .appInactive
                }
                if window?.isKeyWindow != true {
                    return .notKeyWindow
                }
                if window?.attachedSheet != nil {
                    return .sheetAttached
                }
                if environment.coordinator.menuNavigator?.isTrackingMenu == true {
                    return .menuTracking
                }
                if event.window !== window {
                    return .otherWindow
                }
                if event.window?.firstResponder is NSTextView {
                    return .textFieldFocused
                }
                return nil
            }
        }
    #endif
}
