import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI

/// The consoles on the PSN account, rendered from a presented ``AccountConsolesFeature``.
public struct AccountConsolePickerView: View {
    /// The presented console list.
    public let store: StoreOf<AccountConsolesFeature>

    /// The focus of the PS5 and PS4 switch.
    public let kindFocus: MenuFocusState<Bool?>.Binding

    /// The add-console screen's control focus.
    public let focus: MenuFocusState<AddConsoleFocus?>.Binding

    /// The rows the add-console screen moves focus through.
    @Binding public var focusLayout: AccountConsolePickerFocus

    @Environment(\.screenLayout) private var layout

    /// The list.
    public var body: some View {
        VStack(spacing: 14) {
            FocusableSegments(
                options: [true, false],
                title: { ps5 in
                    ps5
                        ? .consolesKindPs5
                        : .consolesKindPs4
                },
                selection: Binding(
                    get: {
                        store.ps5
                    },
                    set: {
                        store.send(.view(.selectGeneration(ps5: $0)))
                    }
                ),
                focus: kindFocus
            )
            switch store.phase {
            case .idle, .loading:
                ProgressView(.consolesAccountPickerLoading).controlSize(.small).padding()
            case .failed:
                Text(.consolesAccountPickerFailed)
                    .font(.callout).foregroundStyle(.secondary)
                FocusButton(.consolesAddConsoleRetry) {
                    store.send(.view(.retry))
                    kindFocus.wrappedValue = store.ps5
                }
                .glassControlStyle()
                .menuFocused(focus, equals: .psnRetry)
            case .ready:
                if store.consoles.isEmpty {
                    Text(.consolesAccountPickerEmpty)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.consoles) { console in
                    FocusButton {
                        store.send(.view(.select(console)))
                    } label: {
                        HStack(spacing: 16) {
                            ConsoleArtwork(
                                height: 64,
                                kind: console.ps5
                                    ? .ps5
                                    : .ps4
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(console.name).font(.headline)
                                Text(
                                    console.remotePlayEnabled
                                        ? .consolesAccountPickerRegister
                                        : .consolesAccountPickerEnableRemotePlay
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .glassEffect(AppGlass.control.interactive(), in: .rect(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .focusHighlightShape(.roundedRectangle(20))
                    .disabled(!console.remotePlayEnabled)
                    .menuFocused(focus, equals: .psnConsole(console.id))
                }
            }
        }
        .onChange(of: currentFocusLayout, initial: true) { _, layout in
            focusLayout = layout
        }
    }

    private var currentFocusLayout: AccountConsolePickerFocus {
        var layout = AccountConsolePickerFocus(ps5: store.ps5)
        switch store.phase {
        case .failed:
            layout.retry = true
        case .ready:
            layout.consoles = store.consoles.filter(\.remotePlayEnabled).map(\.id)
        case .idle, .loading:
            break
        }
        return layout
    }
}

/// The rows of the PSN console list that take controller focus.
public struct AccountConsolePickerFocus: Equatable {
    /// Whether the PS5 segment is selected.
    public var ps5 = true

    /// Whether the Retry button is shown.
    public var retry = false

    /// The device ids of the consoles that can be chosen, in order.
    public var consoles = [Data]()
}

/// The consoles registered to the account on PlayStation Network, to pair one over the internet.
///
/// Presented by ``AddConsoleFeature`` while its PlayStation mode is chosen. Every list request carries the
/// `ChiakiModels/OperationID` that started it; a newer request or a generation change supersedes it.
@Reducer public struct AccountConsolesFeature {
    /// How far listing the consoles has got.
    public enum Phase: Equatable, Sendable {
        /// Nothing was asked yet.
        case idle

        /// The request with this id runs.
        case loading(OperationID)

        /// The consoles are listed.
        case ready

        /// The list could not be read.
        case failed
    }

    /// The listed consoles and the chosen generation.
    @ObservableState public struct State: Equatable {
        /// How far listing has got.
        public internal(set) var phase = Phase.idle

        /// The account's consoles that are not paired yet.
        public internal(set) var consoles: [PSNConsole] = []

        /// Whether PS5 consoles are listed, rather than PS4 ones.
        public internal(set) var ps5 = true

        /// PSN device ids of consoles already paired, which are left out.
        public let excludedDeviceIDs: Set<Data>

        /// The account whose consoles are listed.
        public let accountID: UUID

        /// Opens the list.
        ///
        /// - Parameters:
        ///   - accountID: The account whose consoles are listed.
        ///   - excludedDeviceIDs: PSN device ids to leave out.
        public init(accountID: UUID, excludedDeviceIDs: Set<Data> = []) {
            self.accountID = accountID
            self.excludedDeviceIDs = excludedDeviceIDs
        }
    }

    /// Everything the list reacts to.
    public enum Action: Equatable {
        /// Lists the consoles of the chosen generation.
        case load

        /// Something the user did.
        case view(View)

        /// A list request finished.
        case loaded(OperationID, [PSNConsole])

        /// A list request failed.
        case failed(OperationID)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did.
        @CasePathable
        public enum View: Equatable {
            /// Lists PS5 consoles, or PS4 ones.
            case selectGeneration(ps5: Bool)

            /// Lists again after a failure.
            case retry

            /// Pairs a listed console.
            case select(PSNConsole)
        }

        /// What the list reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The user chose this console to pair.
            case selected(RegistrationFlow.ConsoleTarget)
        }
    }

    @Dependency(\.uuid) private var uuid
    @Dependency(\.consoles) private var client

    private enum CancelID {
        case list
    }

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.selectGeneration(let ps5)):
                state.ps5 = ps5
                return load(&state)
            case .load, .view(.retry):
                return load(&state)
            case .view(.select(let console)):
                guard console.remotePlayEnabled, state.consoles.contains(console) else {
                    return .none
                }
                return .send(.delegate(.selected(.init(
                    address: console.name,
                    kind: console.ps5
                        ? .ps5
                        : .ps4,
                    remoteDeviceID: console.deviceID
                ))))
            case let .loaded(id, consoles):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.phase = .ready
                state.consoles = consoles.filter {
                    !state.excludedDeviceIDs.contains($0.deviceID)
                }
                return .none
            case .failed(let id):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.phase = .failed
                return .none
            case .delegate:
                return .none
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        state.phase = .loading(id)
        state.consoles = []
        return .run { [client, account = state.accountID, ps5 = state.ps5] send in
            do {
                let consoles = try await client.accountConsoles(account, ps5)
                try Task.checkCancellation()
                await send(.loaded(id, consoles))
            } catch is CancellationError {
            } catch {
                await send(.failed(id))
            }
        }
        .cancellable(id: CancelID.list, cancelInFlight: true)
    }
}
