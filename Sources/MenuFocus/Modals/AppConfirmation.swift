import DesignSystem
import PlatformUI
import SwiftUI

/// A request to confirm or cancel a choice, shown by ``SwiftUICore/View/appConfirmation(_:confirm:cancel:)``.
///
/// The app uses this card instead of system alerts and confirmation dialogs, which waste the first
/// controller press, draw the blue system focus ring and drop focus when dismissed.
public struct AppConfirmation: Equatable, Sendable {
    /// How the confirm button is styled.
    public enum Tone: Equatable, Sendable {
        /// An ordinary choice.
        case standard
        /// A choice that destroys something; the confirm button uses the destructive role.
        case destructive
    }

    /// The question asked.
    public var title: String

    /// Extra explanation under the title.
    public var message: String?

    /// An SF Symbol shown above the title.
    public var systemImage: String?

    /// The confirm button's title, or `nil` for a card that can only be dismissed.
    public var confirmTitle: String?

    /// The cancel button's title.
    public var cancelTitle: String

    /// How the confirm button is styled.
    public var tone: Tone

    /// Whether a spinner shows that the choice is being carried out.
    public var progress: Bool

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - title: The question asked.
    ///   - message: Extra explanation under the title.
    ///   - systemImage: An SF Symbol shown above the title.
    ///   - confirmTitle: The confirm button's title, or `nil` for no confirm button.
    ///   - cancelTitle: The cancel button's title.
    ///   - tone: How the confirm button is styled.
    ///   - progress: Whether a spinner shows.
    public init(
        title: String,
        message: String? = nil,
        systemImage: String? = nil,
        confirmTitle: String? = nil,
        cancelTitle: String = "Cancel",
        tone: Tone = .standard,
        progress: Bool = false
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.tone = tone
        self.progress = progress
    }

    /// Whether another request offers the same choice, so the card updates in place instead of being
    /// presented again.
    ///
    /// - Parameter other: Another request.
    /// - Returns: `true` when the title, buttons and tone match.
    public func sameChoice(as other: AppConfirmation) -> Bool {
        title == other.title && confirmTitle == other.confirmTitle && cancelTitle == other.cancelTitle
            && tone == other.tone
    }
}

/// The modal card of an ``AppConfirmation``: the question, an optional explanation and the buttons.
///
/// Focus starts on Cancel, so a stray press never destroys anything. Left and right move between the
/// buttons, back cancels, and a click outside the card cancels. While shown the card owns controller input
/// as a prompt; it releases input the moment a choice is made rather than when its fade-out ends.
public struct AppConfirmationCard: View {
    /// The card's buttons.
    public enum Choice: Hashable, Sendable {
        /// The cancel button.
        case cancel
        /// The confirm button.
        case confirm
    }

    private enum Phase: Equatable {
        case open
        case answered
    }

    private let request: AppConfirmation
    private let confirm: () -> Void
    private let cancel: () -> Void
    @Environment(\.menuNavigator) private var navigator
    @State private var hostWindow: PlatformWindow?
    @State private var phase = Phase.open
    @State private var presentation = UUID()
    @MenuFocusState private var choice: Choice?

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - request: The request to show.
    ///   - confirm: Runs when the user confirms.
    ///   - cancel: Runs when the user cancels.
    public init(request: AppConfirmation, confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.request = request
        self.confirm = confirm
        self.cancel = cancel
    }

    /// The dimmed backdrop and the card.
    public var body: some View {
        ZStack {
            Dimming.light.color
                .contentShape(Rectangle())
                .onTapGesture {
                    finish(cancel)
                }
                .accessibilityLabel("Dismiss")
            card
        }
        .ignoresSafeArea()
        .background(WindowAccessor { hostWindow = $0 })
        .menuHandlers(
            enabled: phase == .open,
            move: { window, direction in
                guard window === hostWindow, phase == .open else {
                    return false
                }
                move(direction)
                return true
            },
            back: { window in
                guard window === hostWindow, phase == .open else {
                    return false
                }
                finish(cancel)
                return true
            }
        )
        .onAppear {
            if phase == .open {
                navigator?.inputGate.block(presentation, prompt: true)
            }
            navigator?.endEditing()
            focusCancel()
        }
        .onDisappear {
            navigator?.inputGate.release(presentation)
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            if let systemImage = request.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(request.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let message = request.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if request.progress {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("In progress")
            }
            buttons
                .padding(.top, 4)
        }
        .padding(32)
        .frame(minWidth: 320, maxWidth: 440)
        .modalCard(.app)
        .menuFocusSection()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            FocusButton(request.cancelTitle) {
                finish(cancel)
            }
            .glassControlStyle()
            .controlSize(.large)
            .menuFocused($choice, equals: .cancel)
            .environment(\.menuMove, move)
            .keyboardShortcut(.cancelAction)
            if let confirmTitle = request.confirmTitle {
                FocusButton(
                    confirmTitle,
                    role: request.tone == .destructive
                        ? .destructive
                        : nil
                ) {
                    finish(confirm)
                }
                .glassProminentControlStyle()
                .controlSize(.large)
                .menuFocused($choice, equals: .confirm)
                .environment(\.menuMove, move)
            }
        }
    }

    private func finish(_ action: () -> Void) {
        guard phase == .open else {
            return
        }
        phase = .answered
        navigator?.inputGate.release(presentation)
        action()
    }

    private func focusCancel() {
        Task { @MainActor in
            for _ in 0..<10 {
                await Task.yield()
                guard phase == .open, choice == nil else {
                    return
                }
                choice = .cancel
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func move(_ direction: MenuMoveDirection) {
        switch direction {
        case .left:
            choice = .cancel
        case .right where request.confirmTitle != nil:
            choice = .confirm
        default:
            if choice == nil {
                choice = .cancel
            }
        }
    }
}

/// Presents an ``AppConfirmationCard`` over content while a request is set, disabling the content.
///
/// A new request with a different choice presents a fresh card, so focus starts on Cancel again. Apply it
/// with ``SwiftUICore/View/appConfirmation(_:confirm:cancel:)``.
public struct AppConfirmationPresentation: ViewModifier {
    private let request: AppConfirmation?
    private let confirm: () -> Void
    private let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation = 0

    /// Creates the presentation.
    ///
    /// - Parameters:
    ///   - request: The request to show, or `nil` for none.
    ///   - confirm: Runs when the user confirms.
    ///   - cancel: Runs when the user cancels, presses back or clicks outside.
    public init(request: AppConfirmation?, confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.request = request
        self.confirm = confirm
        self.cancel = cancel
    }

    /// Overlays the card and disables the content while a request is set.
    ///
    /// - Parameter content: The screen underneath.
    /// - Returns: The screen with the card over it.
    public func body(content: Content) -> some View {
        content
            .disabled(request != nil)
            .overlay {
                if let request {
                    AppConfirmationCard(request: request, confirm: confirm, cancel: cancel)
                        .id(presentation)
                        .transition(AppMotion.transition(reduced: reduceMotion))
                }
            }
            .animation(AppMotion.animation(reduced: reduceMotion), value: request)
            .onChange(of: request) { previous, current in
                if let current, !(previous?.sameChoice(as: current) ?? false) {
                    presentation += 1
                }
            }
    }
}

extension View {
    /// Shows a confirmation card over the view while a request is set.
    ///
    /// - Parameters:
    ///   - request: The request to show, or `nil` for none.
    ///   - confirm: Runs when the user confirms.
    ///   - cancel: Runs when the user cancels.
    /// - Returns: The view with ``AppConfirmationPresentation`` applied.
    public func appConfirmation(
        _ request: AppConfirmation?,
        confirm: @escaping () -> Void = {},
        cancel: @escaping () -> Void
    ) -> some View {
        modifier(AppConfirmationPresentation(request: request, confirm: confirm, cancel: cancel))
    }
}
