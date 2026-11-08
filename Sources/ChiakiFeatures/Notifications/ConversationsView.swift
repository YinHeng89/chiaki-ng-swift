import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The account's PSN conversations inside the Notifications panel, most recently changed first, each opening its
/// conversation in place. Message text shows only inside a conversation, so the list names who and when.
///
/// Back and Refresh share the top row; every conversation is a row of its own. Focus starts on the first
/// conversation, or on Refresh when there is none. Back closes the list; inside an opened conversation Back
/// returns to the list with focus on that conversation.
struct ConversationsView: View {
    /// A focus stop of the list.
    enum Focus: Hashable {
        /// The Back button.
        case back
        /// The Refresh button.
        case refresh
        /// The conversation with this group id.
        case conversation(String)
    }

    /// The list.
    @Bindable var store: StoreOf<ConversationsFeature>
    /// Closes the list.
    let close: () -> Void
    @MenuFocusState private var focus: Focus?
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hostWindow: PlatformWindow?
    @State private var opened: String?

    /// The tallest the list grows before it scrolls.
    static let listHeight: CGFloat = 360

    var body: some View {
        Group {
            if let conversation = store.scope(state: \.conversation, action: \.conversation.presented) {
                ConversationView(store: conversation) {
                    store.send(.conversation(.dismiss))
                }
            } else {
                content
            }
        }
        .background(WindowAccessor { hostWindow = $0 })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            conversations
        }
        .frame(width: 400, alignment: .leading)
        .onAppear {
            store.send(.appeared)
            let returned = opened.flatMap { id in
                store.conversations.contains { $0.id == id }
                    ? Focus.conversation(id)
                    : nil
            }
            opened = nil
            let initial = returned ?? initialFocus
            focus = initial
            FocusRestore.settle(initial) {
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
                    focus = initial
                }
            )
        }
        .onChange(of: store.conversations.first?.id) { _, first in
            guard focus == .refresh, opened == nil, let first else {
                return
            }
            focus = .conversation(first)
        }
        .onMenuExitCommand {
            close()
        }
    }

    private var initialFocus: Focus {
        store.conversations.first.map {
            .conversation($0.id)
        } ?? .refresh
    }

    /// The list's stops, row by row.
    var rows: [[Focus]] {
        Self.rows(for: store.conversations)
    }

    /// The stops of a list, row by row: Back and Refresh, then each conversation.
    ///
    /// - Parameter conversations: The conversations listed.
    /// - Returns: The rows.
    static func rows(for conversations: [PSNConversation]) -> [[Focus]] {
        [[.back, .refresh]] + conversations.map {
            [.conversation($0.id)]
        }
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
            Text(.notificationsConversationsTitle).font(.title3.weight(.semibold))
            Spacer()
            stopButton(.refresh) {
                store.send(.refresh)
            } label: {
                Label(.commonRefresh, systemImage: "arrow.clockwise")
                    .font(.callout.weight(.medium))
            }
            .focusBorderShape(.capsule)
        }
    }

    @ViewBuilder private var conversations: some View {
        if store.conversations.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.conversations) { conversation in
                            row(conversation).id(conversation.id)
                        }
                    }
                    .padding(6)
                }
                .selfManagedFocusScrolling()
                .frame(maxHeight: Self.listHeight)
                .onChange(of: focus) { _, focused in
                    guard case .conversation(let id) = focused else {
                        return
                    }
                    withAnimation(reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id)
                        }
                }
            }
        }
    }

    private var emptyText: LocalizedStringResource {
        switch store.listing {
        case .idle, .loading:
            .notificationsConversationLoading
        case .failed(let failure):
            ConversationView.readFailure(failure)
        case .loaded:
            .notificationsConversationsEmpty
        }
    }

    private func row(_ conversation: PSNConversation) -> some View {
        let stop = Focus.conversation(conversation.id)
        return FocusButton {
            opened = conversation.id
            store.send(.open(conversation.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: conversation.isGroup
                    ? "person.3.fill"
                    : "person.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Palette.accent.opacity(0.22), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    ForEach(Self.details(of: conversation), id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if conversation.unread {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(.notificationsConversationsUnread)
                }
            }
            .padding(8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusWithoutGrowth()
        .focusHighlightShape(.roundedRectangle(10))
        .menuFocused($focus, equals: stop)
        .environment(\.menuMove) { direction in
            move(from: stop, direction)
        }
        .accessibilityElement(children: .combine)
    }

    /// The lines under a conversation's name: who spoke last and when, without the message's text.
    ///
    /// - Parameter conversation: The conversation.
    /// - Returns: The lines.
    static func details(of conversation: PSNConversation) -> [String] {
        var lines: [String] = []
        if let latest = conversation.latest {
            let line: LocalizedStringResource = latest.fromUser
                ? .notificationsConversationsLastFromYou
                : latest.sender.isEmpty
                    ? .notificationsConversationsNewMessage
                    : .notificationsConversationsLastFrom(sender: latest.sender)
            lines.append(String(localized: line))
        }
        if let updated = conversation.updated {
            lines.append(updated.formatted(.relative(presentation: .named)))
        }
        return lines
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
