import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The account sheet the rail's account stop opens: the accounts to switch to, Add, and the selected
/// account's Refresh, Sign in again and Delete.
struct LibraryAccountSheet: View {
    /// A focus stop of the sheet.
    enum Focus: Hashable {
        /// The tile of the account with this id.
        case account(UUID)
        /// The Add tile.
        case add
        /// The Refresh button.
        case refresh
        /// The Sign in again button.
        case signIn
        /// The Delete button.
        case delete
    }

    /// The sheet.
    let store: StoreOf<LibraryAccountSheetFeature>
    /// The saved accounts.
    let profiles: [RegistrationFlow.Profile]
    /// The selected account.
    let selected: RegistrationFlow.Profile?
    /// The selected account's cloud line.
    let cloud: AccountCloudSummary
    /// Whether the account details are being refreshed, which hides Refresh.
    let isRefreshing: Bool
    @Environment(\.dismiss) private var dismiss
    @MenuFocusState private var focus: Focus?
    @Environment(\.menuNavigator) private var navigator
    @State private var hostWindow: PlatformWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selected {
                HStack(spacing: 12) {
                    AccountAvatar(data: selected.avatarData, name: selected.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.name).font(.headline).lineLimit(1)
                        Text(cloud.text)
                            .font(.caption).foregroundStyle(cloud.color).lineLimit(1)
                            .requires(.cloud, of: selected)
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(profiles, id: \.id) { account in
                        tile(account.name, focus: .account(account.id), chosen: account.id == selected?.id) {
                            AccountAvatar(data: account.avatarData, name: account.name)
                        } action: {
                            store.send(.chose(.account(account.id)))
                        }
                    }
                    tile("Add", focus: .add, chosen: false) {
                        AppIcon.addAccount.image
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 34, height: 34)
                    } action: {
                        store.send(.chose(.add))
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)
            HStack(spacing: 10) {
                ForEach(actions, id: \.self) { action in
                    actionButton(action)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 460, alignment: .leading)
        .background(WindowAccessor { hostWindow = $0 })
        .onChange(of: hostWindow) { old, window in
            if let old {
                WindowFocus(old).releaseInput()
            }
            if let window {
                WindowFocus(window).claimInput()
            }
        }
        .onDisappear {
            if let hostWindow {
                WindowFocus(hostWindow).releaseInput()
            }
        }
        .onAppear {
            let initial: Focus = selected.map { .account($0.id) } ?? .add
            focus = initial
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
        .onMenuExitCommand {
            dismiss()
        }
    }

    /// The sheet's focus stops, row by row.
    var rows: [[Focus]] {
        [profiles.map { .account($0.id) } + [.add], actions]
    }

    /// The buttons below the accounts.
    var actions: [Focus] {
        (isRefreshing
            ? []
            : [.refresh]) + (selected == nil
            ? []
            : [.signIn, .delete])
    }

    /// The stop a direction moves focus to.
    ///
    /// - Parameters:
    ///   - current: The focused stop.
    ///   - rows: The sheet's stops, row by row.
    ///   - direction: The direction pressed.
    /// - Returns: The next stop, or `nil` when focus stays.
    nonisolated static func move(from current: Focus, in rows: [[Focus]], _ direction: MenuMoveDirection)
        -> Focus? {
        guard let row = rows.firstIndex(where: { $0.contains(current) }),
              let column = rows[row].firstIndex(of: current) else {
            return nil
        }
        switch direction {
        case .left, .right:
            let next = column + (direction == .left
                ? -1
                : 1)
            return rows[row].indices.contains(next)
                ? rows[row][next]
                : nil
        case .up, .down:
            let next = row + (direction == .up
                ? -1
                : 1)
            guard rows.indices.contains(next), !rows[next].isEmpty else {
                return nil
            }
            return rows[next][min(column, rows[next].count - 1)]
        @unknown default:
            return nil
        }
    }

    private func move(from current: Focus, _ direction: MenuMoveDirection) {
        if let next = Self.move(from: current, in: rows, direction) {
            focus = next
        }
    }

    private func tile(
        _ title: String,
        focus target: Focus,
        chosen: Bool,
        @ViewBuilder image: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        let artwork = image()
        return FocusButton(action: action) {
            VStack(spacing: 8) {
                artwork
                Text(title).font(.caption).lineLimit(1)
                AppIcon.selected.image.font(.caption)
                    .opacity(chosen
                        ? 1
                        : 0)
            }
            .frame(width: 92)
            .padding(.vertical, 10)
        }
        .glassControlStyle()
        .focusBorderShape(.roundedRectangle(14))
        .menuFocused($focus, equals: target)
        .environment(\.menuMove) { direction in
            move(from: target, direction)
        }
        .accessibilityAddTraits(chosen
            ? .isSelected
            : [])
    }

    private func actionButton(_ action: Focus) -> some View {
        FocusButton(role: action == .delete
            ? .destructive
            : nil) {
                perform(action)
            } label: {
                Label(title(of: action), systemImage: icon(of: action).rawValue)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 4)
            }
            .glassControlStyle()
            .focusBorderShape(.capsule)
            .foregroundStyle(action == .delete
                ? Color.red
                : Color.primary)
                .menuFocused($focus, equals: action)
                .environment(\.menuMove) { direction in
                    move(from: action, direction)
                }
    }

    private func perform(_ action: Focus) {
        switch action {
        case .refresh:
            store.send(.chose(.refresh))
        case .signIn:
            if let selected {
                store.send(.chose(.signInAgain(selected.id)))
            }
        case .delete:
            if let selected {
                store.send(.chose(.remove(selected.id)))
            }
        case .account, .add:
            return
        }
    }

    private func title(of action: Focus) -> String {
        switch action {
        case .refresh:
            "Refresh"
        case .signIn:
            "Sign in again"
        case .delete:
            "Delete"
        case .account, .add:
            ""
        }
    }

    private func icon(of action: Focus) -> AppIcon {
        switch action {
        case .refresh:
            .refreshDetails
        case .signIn:
            .signIn
        case .delete:
            .deleteAccount
        case .account, .add:
            .addAccount
        }
    }
}

/// The account sheet the library presents from the rail's account stop.
///
/// The sheet holds no state of its own: it lists the shared accounts and reports the choice, and the library
/// closes it and passes the choice on.
@Reducer public struct LibraryAccountSheetFeature {
    /// What the sheet offers.
    public enum Choice: Equatable, Sendable {
        /// Show the library for this account.
        case account(UUID)
        /// Add an account.
        case add
        /// Refresh the account details.
        case refresh
        /// Sign this account in again.
        case signInAgain(UUID)
        /// Remove this account.
        case remove(UUID)
    }

    /// The sheet's state.
    @ObservableState public struct State: Equatable {
        /// Creates the sheet.
        public init() {
        }
    }

    /// What the sheet can do.
    public enum Action: Equatable, Sendable {
        /// A choice was made.
        case chose(Choice)
    }

    /// Creates the feature.
    public init() {
    }

    /// Runs the sheet; the library handles every choice.
    public var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
