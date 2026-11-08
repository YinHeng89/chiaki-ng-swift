import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// One PSN conversation inside the Notifications panel: a Back button with the conversation's name, its messages
/// oldest first with Earlier messages above them when there are more, and the reply field with Send below it.
///
/// Focus starts on the reply field. Up from the field walks up through the messages, which are read-only stops so
/// a controller can scroll through them, then Earlier messages and Back; Down from the field reaches Send, since
/// Left and Right edit the text, and a message sent from Send hands focus back to the field. Back closes the
/// conversation.
struct ConversationView: View {
    /// A focus stop of the conversation.
    enum Focus: Hashable {
        /// The Back button.
        case back
        /// The Earlier messages button.
        case older
        /// The message with this id.
        case message(String)
        /// The reply field.
        case field
        /// The Send button.
        case send
    }

    /// The conversation.
    let store: StoreOf<ConversationFeature>
    /// Closes the conversation.
    let close: () -> Void
    @MenuFocusState private var focus: Focus?
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hostWindow: PlatformWindow?

    /// The tallest the message list grows before it scrolls.
    static let listHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            messages
            reply
        }
        .frame(width: 400, alignment: .leading)
        .background(WindowAccessor { hostWindow = $0 })
        .onAppear {
            store.send(.appeared)
            focus = .field
            FocusRestore.settle(Focus.field) {
                focus
            } write: { stop in
                focus = stop
            }
            navigator?.ensureFocus(
                in: { hostWindow },
                reset: {},
                apply: {
                    guard focus == nil else {
                        return
                    }
                    focus = .field
                }
            )
        }
        .onChange(of: store.sending) { previous, now in
            guard case .sending = previous, now == .idle, focus == .send else {
                return
            }
            focus = .field
        }
        .onChange(of: Self.showsOlder(store.state)) { _, shown in
            guard !shown, focus == .older else {
                return
            }
            focus = store.messages.first.map {
                .message($0.id)
            } ?? .field
        }
        .onMenuExitCommand {
            close()
        }
    }

    /// The conversation's stops, row by row.
    var rows: [[Focus]] {
        Self.rows(for: store.state)
    }

    /// The stops of a conversation, row by row: Back, Earlier messages when there are more, each message, the
    /// reply field, then Send.
    ///
    /// - Parameter state: The conversation.
    /// - Returns: The rows.
    static func rows(for state: ConversationFeature.State) -> [[Focus]] {
        var rows: [[Focus]] = [[.back]]
        if showsOlder(state) {
            rows.append([.older])
        }
        rows += state.messages.map {
            [.message($0.id)]
        }
        rows.append([.field])
        rows.append([.send])
        return rows
    }

    /// Whether the Earlier messages button shows: messages are shown and older ones exist. It stays while the
    /// newest messages are read again, so a refresh does not take it from under focus.
    ///
    /// - Parameter state: The conversation.
    /// - Returns: `true` when there is more to read.
    static func showsOlder(_ state: ConversationFeature.State) -> Bool {
        !state.complete && !state.messages.isEmpty
    }

    private var header: some View {
        HStack(spacing: 12) {
            stopButton(.back, action: close) {
                Label(.commonBack, systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.callout.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .focusBorderShape(.circle)
            .accessibilityLabel(.notificationsConversationBackToNotifications)
            Text(store.title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Spacer()
        }
    }

    @ViewBuilder private var messages: some View {
        switch store.reading {
        case .idle, .loading:
            if store.messages.isEmpty {
                status(.notificationsConversationLoading)
            } else {
                list
            }
        case .failed(let failure):
            if store.messages.isEmpty {
                status(Self.readFailure(failure))
            } else {
                list
            }
        case .loaded:
            if store.messages.isEmpty {
                status(.notificationsConversationEmpty)
            } else {
                list
            }
        }
    }

    private func status(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if Self.showsOlder(store.state) {
                        stopButton(.older) {
                            store.send(.loadOlder)
                        } label: {
                            Text(olderTitle).font(.callout.weight(.medium))
                        }
                        .focusBorderShape(.capsule)
                        .frame(maxWidth: .infinity)
                        .id("older")
                    }
                    ForEach(store.messages) { message in
                        bubble(message).id(message.id)
                    }
                }
                .padding(6)
            }
            .selfManagedFocusScrolling()
            .frame(height: Self.listHeight)
            .onAppear {
                proxy.scrollTo(store.messages.last?.id, anchor: .bottom)
            }
            .onChange(of: store.messages.last?.id) { _, newest in
                guard focus == .field || focus == .send || focus == nil else {
                    return
                }
                scroll(proxy, to: newest, anchor: .bottom)
            }
            .onChange(of: focus) { _, focused in
                switch focused {
                case .message(let id):
                    scroll(proxy, to: id, anchor: .center)
                case .older:
                    scroll(proxy, to: "older", anchor: .top)
                case .field, .send:
                    scroll(proxy, to: store.messages.last?.id, anchor: .bottom)
                case .back, nil:
                    break
                }
            }
        }
    }

    private var olderTitle: LocalizedStringResource {
        switch store.older {
        case .loading:
            .notificationsConversationOlderLoading
        case .failed:
            .notificationsConversationOlderFailed
        case .idle:
            .notificationsConversationOlder
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String?, anchor: UnitPoint?) {
        guard let id else {
            return
        }
        withAnimation(reduceMotion
            ? nil
            : .easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: anchor)
            }
    }

    private func bubble(_ message: PSNChatMessage) -> some View {
        let stop = Focus.message(message.id)
        return FocusButton {} label: {
            VStack(alignment: message.fromUser
                ? .trailing
                : .leading, spacing: 2) {
                    if !message.fromUser, !message.sender.isEmpty {
                        Text(message.sender)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    messageText(message)
                        .font(message.text == nil
                            ? .callout.italic()
                            : .callout)
                            .foregroundStyle(message.text == nil
                                ? .secondary
                                : .primary)
                                .multilineTextAlignment(message.fromUser
                                    ? .trailing
                                    : .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        message.fromUser
                                            ? Palette.accent.opacity(0.28)
                                            : Color.primary.opacity(0.08),
                                        in: .rect(cornerRadius: 12)
                                    )
                    if let sent = message.sent {
                        Text(sent.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: message.fromUser
                    ? .trailing
                    : .leading)
                    .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusWithoutGrowth()
        .focusHighlightShape(.roundedRectangle(12))
        .menuFocused($focus, equals: stop)
        .environment(\.menuMove) { direction in
            move(from: stop, direction)
        }
    }

    private func messageText(_ message: PSNChatMessage) -> Text {
        guard let text = message.text else {
            return Text(.notificationsConversationUnsupportedMessage)
        }
        return Text(verbatim: text)
    }

    private var reply: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(.notificationsConversationMessagePlaceholder, text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(AppGlass.control, in: .rect(cornerRadius: 12))
                .menuFocusBinding($focus, equals: .field)
                .controllerKeyboard(
                    title: .notificationsConversationMessageKeyboard(name: store.title),
                    text: draft,
                    isFocused: focus == .field
                )
                .onMenuKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                    move(from: .field, press.key == .upArrow
                        ? .up
                        : .down)
                    return .handled
                }
                .onSubmit {
                    store.send(.send)
                }
            HStack {
                if case .failed(let failure) = store.sending {
                    Text(Self.sendFailure(failure))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                stopButton(.send) {
                    store.send(.send)
                } label: {
                    Label(sendTitle, systemImage: "paperplane.fill")
                        .font(.callout.weight(.medium))
                }
                .focusBorderShape(.capsule)
                .opacity(store.canSend
                    ? 1
                    : 0.5)
            }
        }
    }

    private var draft: Binding<String> {
        Binding(
            get: {
                store.draft
            },
            set: { text in
                store.send(.draftChanged(text))
            }
        )
    }

    private var sendTitle: LocalizedStringResource {
        if case .sending = store.sending {
            return .notificationsConversationSending
        }
        return .notificationsConversationSend
    }

    /// What a failed read tells the person.
    ///
    /// - Parameter failure: Why the read failed.
    /// - Returns: The line.
    static func readFailure(_ failure: PSNMessagesFailure) -> LocalizedStringResource {
        switch failure {
        case .signedOut, .auth:
            .notificationsConversationReadSignedOut
        case .rateLimited:
            .notificationsConversationSlowDown
        case .rejected, .unavailable, .cancelled:
            .notificationsConversationReadFailed
        }
    }

    /// What a failed send tells the person.
    ///
    /// - Parameter failure: Why the send failed.
    /// - Returns: The line.
    static func sendFailure(_ failure: PSNMessagesFailure) -> LocalizedStringResource {
        switch failure {
        case .signedOut, .auth:
            .notificationsConversationSendSignedOut
        case .rejected:
            .notificationsConversationSendRejected
        case .rateLimited:
            .notificationsConversationSlowDown
        case .unavailable, .cancelled:
            .notificationsConversationSendFailed
        }
    }

    private func stopButton(
        _ stop: Focus,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        let content = label()
        return FocusButton(action: action) {
            content
        }
        .glassControlStyle()
        .menuFocused($focus, equals: stop)
        .environment(\.menuMove) { direction in
            move(from: stop, direction)
        }
    }

    private func move(from current: Focus, _ direction: MenuMoveDirection) {
        if let next = FocusRows.move(from: current, in: rows, direction) {
            focus = next
        }
    }
}
