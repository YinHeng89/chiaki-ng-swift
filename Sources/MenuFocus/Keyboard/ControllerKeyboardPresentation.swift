import Foundation
import PlatformUI
import SwiftUI

/// Opens the on-screen keyboard for a text field when confirm reaches it with a controller.
///
/// While the field has focus, confirm opens the keyboard as a sheet; it also opens when
/// `presentationRequest` increases. The keyboard owns controller input while shown. When it closes, focus
/// returns to the field, or `onDismiss` decides where it goes. Apply it with
/// `controllerKeyboard(title:text:isFocused:)`.
public struct ControllerKeyboardPresentation: ViewModifier {
    @MainActor
    private final class Activation {
        var accepts: (PlatformWindow) -> Bool = { _ in
            false
        }
        var id: MenuHandlerID?
    }

    private let title: String
    @Binding private var text: String
    private let isFocused: Bool
    private let secure: Bool
    private let numberPad: Bool
    private let allowsNewline: Bool
    private let presentationRequest: Int
    private let presentationWindow: PlatformWindow?
    private let onDismiss: ((Bool) -> Void)?
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.touchKeyboard) private var touchKeyboard
    @State private var session: ControllerKeyboardSession?
    @State private var presentationID = UUID()
    @State private var activation = Activation()

    /// Creates the presentation.
    ///
    /// - Parameters:
    ///   - title: The keyboard's title, usually the field's label.
    ///   - text: The field's text.
    ///   - isFocused: Whether the field has focus now.
    ///   - secure: Whether the field hides its text.
    ///   - numberPad: Whether to show the number pad.
    ///   - allowsNewline: Whether the keyboard offers Return.
    ///   - presentationRequest: Opens the keyboard each time it increases.
    ///   - presentationWindow: The window to present over for a request, the key window when `nil`.
    ///   - onDismiss: Decides where focus goes when the keyboard closes; receives whether Done was chosen.
    public init(
        title: String,
        text: Binding<String>,
        isFocused: Bool,
        secure: Bool,
        numberPad: Bool,
        allowsNewline: Bool,
        presentationRequest: Int,
        presentationWindow: PlatformWindow?,
        onDismiss: ((Bool) -> Void)?
    ) {
        self.title = title
        _text = text
        self.isFocused = isFocused
        self.secure = secure
        self.numberPad = numberPad
        self.allowsNewline = allowsNewline
        self.presentationRequest = presentationRequest
        self.presentationWindow = presentationWindow
        self.onDismiss = onDismiss
    }

    /// Attaches the keyboard sheet and its activation handler to the field.
    ///
    /// - Parameter content: The text field.
    /// - Returns: The field that opens the keyboard on confirm.
    public func body(content: Content) -> some View {
        activation.accepts = accepts
        return content
        #if os(iOS)
            .overlay {
                if let touchKeyboard, navigator?.inputMode.mode != .controller {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            touchKeyboard(touchRequest)
                        }
                }
            }
        #endif
            .onAppear {
                registerActivation()
            }
            .onChange(of: presentationRequest) { _, request in
                guard request > 0,
                      session == nil,
                      let window = presentationWindow ?? WindowFocus.keyWindow else {
                    return
                }
                open(in: window)
            }
            .sheet(item: $session) {
                navigator?.inputGate.release(presentationID)
            } content: { session in
                ControllerOnScreenKeyboard(
                    title: title,
                    text: $text,
                    secure: secure,
                    numberPad: numberPad,
                    allowsNewline: allowsNewline,
                    sourceWindow: session.window,
                    dismiss: { advance in
                        close(session, advance: advance)
                    }
                )
                .presentationSizing(.fitted)
                .environment(\.settingsMenuFocus, false)
            }
            .onDisappear {
                navigator?.inputGate.release(presentationID)
                if let id = activation.id {
                    navigator?.handlers.unregister(id)
                    activation.id = nil
                }
            }
    }

    private var touchRequest: TouchKeyboardRequest {
        TouchKeyboardRequest(
            title: title,
            prompt: title,
            text: $text,
            kind: numberPad
                ? .number
                : .text,
            multiline: allowsNewline,
            secure: secure
        )
    }

    private func registerActivation() {
        guard activation.id == nil, let navigator else {
            return
        }
        let activation = activation
        activation.id = navigator.handlers.registerTextActivation { window in
            activation.accepts(window)
        }
    }

    private func accepts(_ window: PlatformWindow) -> Bool {
        guard isFocused, session == nil, navigator?.focusAcceptsControllerKeyboard(in: window) == true else {
            return false
        }
        open(in: window)
        return true
    }

    private func open(in window: PlatformWindow) {
        let origin = navigator?.editingFocusOrigin(in: window)
        navigator?.inputGate.block(presentationID)
        session = ControllerKeyboardSession(window: window, origin: origin)
    }

    private func close(_ closing: ControllerKeyboardSession, advance: Bool) {
        session = nil
        if let onDismiss {
            onDismiss(advance)
            return
        }
        guard let origin = closing.origin, let navigator else {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            await navigator.restoreFocus(to: origin, in: closing.window, advance: advance)
        }
    }
}

extension View {
    /// Lets a controller type into this text field with the on-screen keyboard.
    ///
    /// - Parameters:
    ///   - title: The keyboard's title, usually the field's label.
    ///   - text: The field's text.
    ///   - isFocused: Whether the field has focus now.
    ///   - secure: Whether the field hides its text.
    ///   - numberPad: Whether to show the number pad.
    ///   - allowsNewline: Whether the keyboard offers Return.
    ///   - presentationRequest: Opens the keyboard each time it increases.
    ///   - presentationWindow: The window to present over for a request, the key window when `nil`.
    ///   - onDismiss: Decides where focus goes when the keyboard closes; receives whether Done was chosen.
    /// - Returns: The field with ``ControllerKeyboardPresentation`` applied.
    public func controllerKeyboard(
        title: String,
        text: Binding<String>,
        isFocused: Bool,
        secure: Bool = false,
        numberPad: Bool = false,
        allowsNewline: Bool = false,
        presentationRequest: Int = 0,
        presentationWindow: PlatformWindow? = nil,
        onDismiss: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(ControllerKeyboardPresentation(
            title: title,
            text: text,
            isFocused: isFocused,
            secure: secure,
            numberPad: numberPad,
            allowsNewline: allowsNewline,
            presentationRequest: presentationRequest,
            presentationWindow: presentationWindow,
            onDismiss: onDismiss
        ))
    }
}

/// One showing of the on-screen keyboard: the window it covers and the field to return focus to.
private struct ControllerKeyboardSession: Identifiable {
    /// The session's identity, which keys the sheet.
    let id = UUID()

    /// The window the keyboard was opened from.
    let window: PlatformWindow

    /// The text field that had focus, to return focus to when the keyboard closes.
    let origin: FocusOrigin?
}
