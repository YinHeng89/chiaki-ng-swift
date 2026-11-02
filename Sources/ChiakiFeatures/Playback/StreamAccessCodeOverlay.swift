import ChiakiModels
import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

/// A modal card over the stream that asks for a four digit console login PIN or controller passcode, with
/// controller navigation and an on screen number pad, and reports a valid code or a cancel.
///
/// On a compact screen the card drops its icon and tightens its spacing. While the software keyboard takes the
/// bottom of the screen the card sits at the top, so the digits and buttons stay visible above it.
struct StreamAccessCodeOverlay: View {
    /// The menu navigator that routes controller moves and activation to the card while it is shown.
    @Environment(\.menuNavigator) var navigator
    private enum FocusTarget: Hashable {
        case code, cancel, `continue`
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout
    @State private var code = ""
    @State private var presentationID = UUID()
    @State private var keyboardRequest = 0
    @State private var controllerFocus = FocusTarget.code
    @State private var hostWindow: PlatformWindow?
    @State private var keyboardWindow: PlatformWindow?
    @MenuFocusState private var focused: FocusTarget?
    @State private var focusMoveHandlerID: MenuHandlerID?
    @State private var activationHandlerID: MenuHandlerID?
    /// The access request phase that decides whether the card shows, which prompt it asks and whether it is
    /// submitting or was rejected.
    let phase: StreamAccessPhase
    /// The name of the player joining, used in the controller passcode wording when known.
    var playerName: String?
    /// Receives the entered code when Continue is chosen with four digits.
    let submit: @MainActor @Sendable (StreamAccessCode) -> Void
    /// Runs when the entry is cancelled, including a click outside the card.
    let cancel: @MainActor @Sendable () -> Void

    private var prompt: StreamAccessPrompt? {
        switch phase {
        case .requested(let prompt), .submitting(_, let prompt), .failed(let prompt):
            prompt
        case .idle, .recalling:
            nil
        }
    }

    private var submitting: Bool {
        if case .submitting = phase {
            return true
        }
        return false
    }

    private var rejected: Bool {
        if case .failed = phase {
            return true
        }
        switch prompt {
        case .loginPIN(let retry), .controllerPasscode(_, let retry):
            return retry
        case nil:
            return false
        }
    }

    private var compact: Bool {
        layout.isCompact
    }

    var body: some View {
        if let prompt {
            GeometryReader { proxy in
                let room = proxy.size
                let keyboardShown = proxy.safeAreaInsets.bottom > 0
                ZStack(alignment: keyboardShown
                    ? .top
                    : .center) {
                        Dimming.standard.color
                            .contentShape(Rectangle())
                            .accessibilityLabel("Cancel code entry")
                        VStack(spacing: compact
                            ? 10
                            : 20) {
                                if !compact {
                                    Image(systemName: symbol(for: prompt))
                                        .font(.system(size: 24, weight: .medium))
                                        .frame(width: 52, height: 52)
                                        .glassEffect(AppGlass.control, in: .circle)
                                }
                                VStack(spacing: compact
                                    ? 3
                                    : 7) {
                                        Text(title(for: prompt))
                                            .font(compact
                                                ? .headline
                                                : .title2.weight(.semibold))
                                        Text(detail(for: prompt))
                                            .font(compact
                                                ? .caption
                                                : .subheadline)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(compact
                                                    ? 2
                                                    : nil)
                                                    .fixedSize(horizontal: false, vertical: !compact)
                                    }
                                accessField(for: prompt)
                                if rejected {
                                    Label(
                                        "That code wasn’t accepted. Try again.",
                                        systemImage: "exclamationmark.circle"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .transition(.opacity)
                                }
                                HStack(spacing: 12) {
                                    FocusButton(action: cancel) {
                                        Text("Cancel")
                                            .frame(maxWidth: .infinity, minHeight: layout.controlSize)
                                    }
                                    .glassControlStyle()
                                    .menuFocused($focused, equals: .cancel)
                                    .environment(\.menuItemFocused, controllerFocus == .cancel)
                                    .keyboardShortcut(.cancelAction)
                                    .frame(maxWidth: .infinity)
                                    FocusButton(action: submitCode) {
                                        if submitting {
                                            ProgressView()
                                                .controlSize(.small)
                                                .frame(maxWidth: .infinity, minHeight: layout.controlSize)
                                        } else {
                                            Text("Continue")
                                                .frame(maxWidth: .infinity, minHeight: layout.controlSize)
                                        }
                                    }
                                    .glassProminentControlStyle()
                                    .menuFocused($focused, equals: .continue)
                                    .environment(\.menuItemFocused, controllerFocus == .continue)
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(code.count != 4 || submitting)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(compact
                                ? 16
                                : 28)
                                .frame(width: min(410, room.width - 2 * max(16, layout.sideInset)))
                                .menuFocusSection()
                                .menuDefaultFocus($focused, .code)
                                .controllerKeyboard(
                                    title: title(for: prompt),
                                    text: codeBinding,
                                    isFocused: focused == .code,
                                    secure: true,
                                    numberPad: true,
                                    presentationRequest: keyboardRequest,
                                    presentationWindow: keyboardWindow ?? hostWindow,
                                    onDismiss: { advance in
                                        controllerFocus = advance && code.count == 4
                                            ? .continue
                                            : .code
                                        focused = controllerFocus
                                    }
                                )
                                .modalCard(.overlay)
                                .padding(.top, keyboardShown
                                    ? 8
                                    : 0)
                                    .background(
                                        DismissOnOutsideClick(active: true, dismiss: cancel)
                                    )
                                    .transition(
                                        reduceMotion
                                            ? .opacity
                                            : .scale(scale: 0.96).combined(with: .opacity)
                                    )
                    }
                    .background(WindowAccessor { hostWindow = $0 })
                    .onAppear {
                        navigator?.inputGate.presentations.insert(presentationID)
                        controllerFocus = .code
                        focused = .code
                        Task { @MainActor in
                            await Task.yield()
                            guard prompt == self.prompt else {
                                return
                            }
                            focused = .code
                            keepCodeFocus()
                        }
                        focusMoveHandlerID = navigator?.handlers.registerFocusMove { window, direction in
                            guard !PlaybackWindowControl.hasAttachedSheet(window) else {
                                return false
                            }
                            moveFocus(direction)
                            return true
                        }
                        activationHandlerID = navigator?.handlers.registerModalActivation { window in
                            guard !PlaybackWindowControl.hasAttachedSheet(window) else {
                                return false
                            }
                            switch controllerFocus {
                            case .code:
                                focused = .code
                                keyboardWindow = window
                                keyboardRequest += 1
                            case .cancel:
                                cancel()
                            case .continue:
                                submitCode()
                            }
                            return true
                        }
                    }
                    .onChange(of: phase) { _, value in
                        switch value {
                        case .requested, .failed:
                            controllerFocus = .code
                            focused = .code
                            keepCodeFocus()
                        case .submitting, .idle, .recalling:
                            focused = nil
                        }
                    }
                    .onDisappear {
                        navigator?.inputGate.presentations.remove(presentationID)
                        if let focusMoveHandlerID {
                            navigator?.handlers.unregister(focusMoveHandlerID)
                        }
                        if let activationHandlerID {
                            navigator?.handlers.unregister(activationHandlerID)
                        }
                    }
            }
        }
    }
}

extension StreamAccessCodeOverlay {
    private func beginTyping() {
        controllerFocus = .code
        focused = .code
        #if os(iOS)
            let window = hostWindow
            let navigator = navigator
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                navigator?.beginEditing(in: window)
            }
        #endif
    }

    private func submitCode() {
        guard let accessCode = StreamAccessCode(code), !submitting else {
            return
        }
        focused = nil
        submit(accessCode)
    }

    private func keepCodeFocus() {
        navigator?.ensureFocus(
            in: { hostWindow },
            reset: {},
            apply: {
                guard focused == nil else {
                    return
                }
                focused = controllerFocus
            }
        )
    }

    private func moveFocus(_ direction: MenuMoveDirection) {
        switch direction {
        case .up:
            controllerFocus = .code
        case .down:
            if controllerFocus == .code {
                controllerFocus = .cancel
            }
        case .left:
            if controllerFocus == .continue {
                controllerFocus = .cancel
            }
        case .right:
            if controllerFocus == .cancel, code.count == 4, !submitting {
                controllerFocus = .continue
            }
        @unknown default:
            break
        }
        focused = controllerFocus
    }

    @ViewBuilder
    private func accessField(for prompt: StreamAccessPrompt) -> some View {
        switch prompt {
        case .loginPIN:
            ZStack {
                HStack(spacing: 10) {
                    ForEach(0 ..< 4, id: \.self) { index in
                        pinDigit(index)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Palette.accent.opacity(
                            controllerFocus == .code
                                ? 0.14
                                : 0
                        ))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Palette.accent.opacity(
                            controllerFocus == .code
                                ? 0.9
                                : 0
                        ), lineWidth: 2)
                }
                SecureField("Console login PIN", text: codeBinding)
                    .textFieldStyle(.plain)
                    .menuFocused($focused, equals: .code)
                    .onSubmit(submitCode)
                    .opacity(0.02)
                    .frame(width: 246, height: 54)
                    .accessibilityLabel("Four-digit console login PIN")
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
            }
            .contentShape(Rectangle())
            .onTapGesture {
                beginTyping()
            }
        case .controllerPasscode(let pad, _):
            SecureField("Four-digit controller passcode", text: codeBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .glassEffect(AppGlass.control, in: .rect(cornerRadius: 15))
                .menuFocused($focused, equals: .code)
                .onSubmit(submitCode)
                .accessibilityLabel("Four-digit passcode for Player \(pad)")
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
        }
    }

    private func pinDigit(_ index: Int) -> some View {
        let filled = index < code.count
        return Image(
            systemName: filled
                ? "circle.fill"
                : "\(index + 1).circle"
        )
        .font(
            .system(
                size: filled
                    ? 12
                    : 18,
                weight: .medium
            )
        )
        .foregroundStyle(
            filled
                ? .primary
                : .secondary
        )
        .frame(width: 54, height: 54)
        .glassEffect(AppGlass.control, in: .rect(cornerRadius: 15))
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: {
                code
            },
            set: { value in
                let scalars = value.unicodeScalars.filter {
                    (48 ... 57).contains($0.value)
                }
                code = String(String.UnicodeScalarView(scalars.prefix(4)))
            }
        )
    }

    private func symbol(for prompt: StreamAccessPrompt) -> String {
        switch prompt {
        case .loginPIN:
            "lock.shield"
        case .controllerPasscode:
            "gamecontroller"
        }
    }

    private func title(for prompt: StreamAccessPrompt) -> String {
        switch prompt {
        case .loginPIN:
            "Console login PIN"
        case .controllerPasscode:
            "Controller passcode"
        }
    }

    private func detail(for prompt: StreamAccessPrompt) -> String {
        switch prompt {
        case .loginPIN:
            "Enter the four-digit PIN configured for console login."
        case .controllerPasscode(let pad, _):
            if let playerName {
                "Enter the four-digit user passcode for \(playerName), joining as Player \(Int(pad) + 1)."
            } else {
                "Enter the four-digit user passcode for Player \(Int(pad) + 1)."
            }
        }
    }
}

#Preview("Console login PIN") {
    ZStack {
        Color(red: 0.04, green: 0.08, blue: 0.13)
        StreamAccessCodeOverlay(
            phase: .requested(.loginPIN(retry: false)),
            submit: { _ in },
            cancel: {}
        )
    }
    .frame(width: 900, height: 560)
}

#Preview("Controller passcode") {
    ZStack {
        Color(red: 0.04, green: 0.08, blue: 0.13)
        StreamAccessCodeOverlay(
            phase: .requested(.controllerPasscode(pad: 2, retry: true)),
            submit: { _ in },
            cancel: {}
        )
    }
    .frame(width: 900, height: 560)
}
